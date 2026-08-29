import AVFoundation
import Foundation

/// 文字や名前を日本語で読み上げる。
///
/// `AVSpeechSynthesizer` は読み上げ中に解放されると発話が途切れるため、共有インスタンスで保持する。
/// 日本語の音声が入っていない端末では何もしない (読み上げが無くても操作は続けられる)。
@MainActor
final class SpeechReader {
  static let shared = SpeechReader()

  private let synthesizer = AVSpeechSynthesizer()

  /// 子どもが音を追えるよう、標準よりゆっくり読み上げる。
  private let rate = AVSpeechUtteranceDefaultSpeechRate * 0.7

  private init() {}

  func speak(_ text: String) {
    guard !text.isEmpty else {
      return
    }

    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
    utterance.rate = rate
    utterance.pitchMultiplier = 1.15
    synthesizer.speak(utterance)
  }

  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
  }
}
