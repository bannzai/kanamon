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
  /// `AVSpeechSynthesizerDelegate` が Sendable を要求する一方 `AVSpeechSynthesizer` は Sendable ではないため、
  /// 受け渡しの安全性はこのクラスの lock で担保していることを nonisolated(unsafe) で明示する。
  nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
  /// 読み終わりの通知が発話とは別のスレッドで届くため、continuation の受け渡しを直列化する。
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var timeoutTask: Task<Void, Never>?

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

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      lock.lock()
      self.continuation = continuation
      lock.unlock()

      startTimeout(characterCount: text.count)
      synthesizer.speak(utterance)
    }
  }

  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
    finishSpeaking()
  }

  /// 読み終わりの通知が届かない環境でも先へ進めるための保険。
  /// 実際の読み上げより必ず長くなるよう、文字数に比例させる (1 文字あたり 0.7 秒 + 余裕 1.0 秒)。
  private static func timeoutDuration(characterCount: Int) -> Duration {
    .milliseconds(1000 + 700 * max(1, characterCount))
  }

  private func startTimeout(characterCount: Int) {
    let duration = Self.timeoutDuration(characterCount: characterCount)
    let timeoutTask = Task { [weak self] in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else {
        return
      }
      self?.finishSpeaking()
    }

    lock.lock()
    self.timeoutTask = timeoutTask
    lock.unlock()
  }

  /// 読み終わり・中断・時間切れのどれから呼ばれても 1 回だけ continuation を再開する。
  private func finishSpeaking() {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    let timeoutTask = self.timeoutTask
    self.timeoutTask = nil
    lock.unlock()

    timeoutTask?.cancel()
    continuation?.resume()
  }
}

extension JapaneseSpeechSynthesizer: AVSpeechSynthesizerDelegate {
  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    finishSpeaking()
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    finishSpeaking()
  }
}
