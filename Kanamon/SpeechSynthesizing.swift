import AVFoundation
import Foundation

/// 文字や名前を音声で読み上げ、読み終わりまで待てる読み上げ機能を表す。
protocol SpeechSynthesizing: AnyObject {
  /// 読み終わる (または中断される) まで待ってから返る。`rate` は `AVSpeechUtterance` の尺度 (既定 0.5)。
  func speak(text: String, rate: Float) async
  func stop()
}

/// `AVSpeechSynthesizer` で日本語を読み上げる。
///
/// 読み上げ中に解放されると発話が止まるため、`AVSpeechSynthesizer` はプロパティとして保持し続ける。
final class JapaneseSpeechSynthesizer: NSObject, SpeechSynthesizing {
  /// 画面をまたいで 1 つの `AVSpeechSynthesizer` から読み上げる。
  /// インスタンスごとに `AVSpeechSynthesizer` を持つと、別の画面の発話と重なって鳴るため。
  static let shared = JapaneseSpeechSynthesizer()

  /// 待たせている 1 回分の読み上げ。読み終わりの通知・時間切れが、どの発話に対するものかを見分けるために持つ。
  private struct SpeakingRequest {
    /// 発話を始めた順の通し番号。時間切れの Task が自分の発話かどうかを確かめるのに使う。
    let generation: Int
    let utterance: AVSpeechUtterance
    let continuation: CheckedContinuation<Void, Never>
    let timeoutTask: Task<Void, Never>
  }

  /// `AVSpeechSynthesizerDelegate` が Sendable を要求する一方 `AVSpeechSynthesizer` は Sendable ではないため、
  /// 受け渡しの安全性はこのクラスの lock で担保していることを nonisolated(unsafe) で明示する。
  nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
  /// 読み終わりの通知が発話とは別のスレッドで届くため、リクエストの受け渡しを直列化する。
  ///
  /// `stopSpeaking` が同じスレッドで同期的に届ける `didCancel` から `finishSpeaking` に入るため、
  /// 取り外しから登録までを 1 度の lock 区間にできるよう再帰ロックにする。
  private let lock = NSRecursiveLock()
  private var currentRequest: SpeakingRequest?
  private var generationCounter = 0

  /// 子ども向けに少し高い声にする。1.0 が地声で、上げすぎると聞き取りにくくなるため小さめに振る。
  private static let pitchMultiplier: Float = 1.15
  private static let languageCode = "ja-JP"

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speak(text: String, rate: Float) async {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: Self.languageCode)
    utterance.rate = rate
    utterance.pitchMultiplier = Self.pitchMultiplier

    // クイズ画面は別の `AVSpeechSynthesizer` にキューを積むため、こちらの発話に重ならないよう先に止める
    await MainActor.run { SpeechSynthesizer.shared.stop() }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      // 取り外しから登録までを 1 度の lock 区間で行い、並行して呼ばれた時に
      // currentRequest が上書きされて前の continuation が残らないようにする
      lock.lock()
      let previousRequest = detachCurrentRequestWithLockHeld()
      generationCounter += 1
      let generation = generationCounter
      currentRequest = SpeakingRequest(
        generation: generation,
        utterance: utterance,
        continuation: continuation,
        timeoutTask: makeTimeoutTask(generation: generation, characterCount: text.count)
      )
      synthesizer.speak(utterance)
      lock.unlock()

      // 待たせていた呼び出し元を返すのは、その先の処理が lock 区間に入ってこないよう lock を出てから行う
      previousRequest?.timeoutTask.cancel()
      previousRequest?.continuation.resume()
    }
  }

  func stop() {
    stopCurrentSpeaking()
  }

  /// 読み終わりの通知が届かない環境でも先へ進めるための保険。
  /// 実際の読み上げより必ず長くなるよう、文字数に比例させる (1 文字あたり 0.7 秒 + 余裕 1.0 秒)。
  private static func timeoutDuration(characterCount: Int) -> Duration {
    .milliseconds(1000 + 700 * max(1, characterCount))
  }

  private func makeTimeoutTask(generation: Int, characterCount: Int) -> Task<Void, Never> {
    let duration = Self.timeoutDuration(characterCount: characterCount)

    return Task { [weak self] in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else {
        return
      }

      self?.finishSpeaking { $0.generation == generation }
    }
  }

  /// 進行中の発話を止めて、待っている呼び出し元を返す。発話していない時に呼んでも何も起きない。
  private func stopCurrentSpeaking() {
    lock.lock()
    let request = detachCurrentRequestWithLockHeld()
    lock.unlock()

    request?.timeoutTask.cancel()
    request?.continuation.resume()
  }

  /// 進行中の発話を取り外して止め、待たせている リクエスト を返す。
  ///
  /// `lock` を保持したまま呼ぶ。返したリクエストの後始末 (時間切れの取り消しと continuation の再開) は
  /// 呼び出し元が lock を出てから行う。
  private func detachCurrentRequestWithLockHeld() -> SpeakingRequest? {
    let request = currentRequest
    currentRequest = nil
    // 取り外してから止めることで、stopSpeaking が同期で届ける didCancel が次の発話に効かないようにする
    synthesizer.stopSpeaking(at: .immediate)

    return request
  }

  /// 読み終わり・時間切れのどちらから呼ばれても 1 回だけ continuation を再開する。
  /// 古い発話から遅れて届いた通知で次の発話を終わらせないよう、`isTarget` で対応を確かめてから再開する。
  private func finishSpeaking(isTarget: (SpeakingRequest) -> Bool) {
    lock.lock()
    guard let request = currentRequest, isTarget(request) else {
      lock.unlock()
      return
    }
    currentRequest = nil
    lock.unlock()

    request.timeoutTask.cancel()
    request.continuation.resume()
  }
}

extension JapaneseSpeechSynthesizer: AVSpeechSynthesizerDelegate {
  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    finishSpeaking { $0.utterance === utterance }
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    finishSpeaking { $0.utterance === utterance }
  }
}
