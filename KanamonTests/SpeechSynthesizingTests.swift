import AVFoundation
import Foundation
import XCTest

@testable import Kanamon

/// `JapaneseSpeechSynthesizer` の待ち合わせを、実機の音声合成に触れずに確かめる。
///
/// CI の runner では音声が出ず `AVSpeechSynthesizer.speak` が返らないため、合成器はフェイクに差し替える。
final class SpeechSynthesizingTests: XCTestCase {
  /// 1 音をはっきり読ませる `YomiRenshuModel` と同じ速さ。
  private static let rate: Float = 0.4
  /// テストが待ちに入ってから合成器の呼び出しを観測するまでの上限。ローカル・CI ともに数 ms で済む処理のため短くてよい
  private static let observeTimeoutSeconds: TimeInterval = 3

  /// 同時に呼んだ speak は、合成器が読み終わりを返せば 2 つとも返る。
  func testConcurrentSpeakCallsBothReturn() async {
    let speaker = UtteranceSpeakerFake()
    let synthesizer = JapaneseSpeechSynthesizer(synthesizer: speaker, stopOtherSpeech: {})
    speaker.endsUtteranceImmediately = { [weak synthesizer] utterance in
      synthesizer?.utteranceDidEnd(utterance)
    }

    await withTaskGroup(of: Void.self) { group in
      group.addTask { await synthesizer.speak(text: "ア", rate: Self.rate) }
      group.addTask { await synthesizer.speak(text: "イ", rate: Self.rate) }
    }

    XCTAssertEqual(speaker.spokenTexts.sorted(), ["ア", "イ"])
  }

  /// 読み終わりが届かない発話も、stop() で待たせている呼び出し元が返る。
  func testStopReturnsWaitingSpeak() async {
    let speaker = UtteranceSpeakerFake()
    let synthesizer = JapaneseSpeechSynthesizer(synthesizer: speaker, stopOtherSpeech: {})

    let speaking = Task { await synthesizer.speak(text: "アイウ", rate: Self.rate) }
    await waitUntil(message: "発話が合成器に渡らなかった") { speaker.spokenTexts.count == 1 }

    let stopCountBeforeStop = speaker.stopCount
    synthesizer.stop()
    await speaking.value

    XCTAssertEqual(speaker.stopCount, stopCountBeforeStop + 1)
  }

  /// speak が他画面の停止を待っている間に stop() されたら、その後で発話を始めずに返る。
  func testStopWhileSpeakIsSuspendedPreventsLateStart() async {
    let speaker = UtteranceSpeakerFake()
    var synthesizer: JapaneseSpeechSynthesizer!
    // 他画面の停止 (speak の待ち合わせ中) のタイミングで、この読み上げ自身の stop() を呼ぶ
    synthesizer = JapaneseSpeechSynthesizer(synthesizer: speaker, stopOtherSpeech: { synthesizer.stop() })

    await synthesizer.speak(text: "ア", rate: Self.rate)

    XCTAssertTrue(speaker.spokenTexts.isEmpty, "stop() の後で発話が始まっている")
  }

  /// 前の発話が読み終わらないまま次の speak が来たら、前の呼び出し元を返してから次を読む。
  func testNextSpeakReplacesPendingOne() async {
    let speaker = UtteranceSpeakerFake()
    let synthesizer = JapaneseSpeechSynthesizer(synthesizer: speaker, stopOtherSpeech: {})

    let first = Task { await synthesizer.speak(text: "ア", rate: Self.rate) }
    await waitUntil(message: "1 つ目の発話が合成器に渡らなかった") { speaker.spokenTexts.count == 1 }
    let second = Task { await synthesizer.speak(text: "イ", rate: Self.rate) }
    await waitUntil(message: "2 つ目の発話が合成器に渡らなかった") { speaker.spokenTexts.count == 2 }

    await first.value
    XCTAssertEqual(speaker.spokenTexts, ["ア", "イ"])

    // 2 つ目は読み終わりを返して片付ける
    speaker.spokenUtterances.last.map { synthesizer.utteranceDidEnd($0) }
    await second.value
  }

  /// 古い発話の読み終わりが遅れて届いても、次の発話を終わらせない。
  func testStaleUtteranceEndDoesNotFinishNextSpeak() async {
    let speaker = UtteranceSpeakerFake()
    let synthesizer = JapaneseSpeechSynthesizer(synthesizer: speaker, stopOtherSpeech: {})

    let first = Task { await synthesizer.speak(text: "ア", rate: Self.rate) }
    await waitUntil(message: "1 つ目の発話が合成器に渡らなかった") { speaker.spokenTexts.count == 1 }
    let staleUtterance = speaker.spokenUtterances[0]
    let second = Task { await synthesizer.speak(text: "イ", rate: Self.rate) }
    await waitUntil(message: "2 つ目の発話が合成器に渡らなかった") { speaker.spokenTexts.count == 2 }
    await first.value

    synthesizer.utteranceDidEnd(staleUtterance)
    var secondFinished = false
    let observer = Task {
      await second.value
      secondFinished = true
    }
    // 古い通知で 2 つ目が終わっていないことを、少し待ってから確かめる (即座に終わる場合はここで観測できる)
    try? await Task.sleep(for: .milliseconds(100))
    XCTAssertFalse(secondFinished, "古い発話の読み終わりで次の発話が終わっている")

    synthesizer.utteranceDidEnd(speaker.spokenUtterances[1])
    await observer.value
    XCTAssertTrue(secondFinished)
  }

  private func waitUntil(
    message: String,
    condition: @escaping () -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(Self.observeTimeoutSeconds)
    while !condition() {
      if Date() > deadline {
        XCTFail(message)
        return
      }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }
}

/// 音を出さずに、渡された発話と停止の回数を記録するだけの合成器。
private final class UtteranceSpeakerFake: UtteranceSpeaking, @unchecked Sendable {
  private let lock = NSLock()
  private var _spokenUtterances: [AVSpeechUtterance] = []
  private var _stopCount = 0

  weak var delegate: (any AVSpeechSynthesizerDelegate)?
  /// 設定すると、発話を受け取った直後にその発話の読み終わりを返す。
  var endsUtteranceImmediately: ((AVSpeechUtterance) -> Void)?

  var spokenUtterances: [AVSpeechUtterance] {
    lock.lock()
    defer { lock.unlock() }
    return _spokenUtterances
  }

  var spokenTexts: [String] {
    spokenUtterances.map(\.speechString)
  }

  var stopCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return _stopCount
  }

  func speak(_ utterance: AVSpeechUtterance) {
    lock.lock()
    _spokenUtterances.append(utterance)
    lock.unlock()
    endsUtteranceImmediately?(utterance)
  }

  @discardableResult
  func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    _stopCount += 1
    return true
  }
}
