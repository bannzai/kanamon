import AVFoundation

/// なまえ や もじ を日本語の音声で読み上げる。文字と音を結びつけられるようにするために使う。
///
/// 読み上げ中に続けて渡した文は `AVSpeechSynthesizer` が順番に読むため、選択肢の名前のあとに
/// 「もう いちど」を続けて渡してもどちらも読まれる。
@MainActor
final class SpeechSynthesizer {
  static let shared = SpeechSynthesizer()

  private let synthesizer = AVSpeechSynthesizer()

  private init() {}

  func speak(_ text: String, rate: Float = 0.45) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
    utterance.rate = rate
    synthesizer.speak(utterance)
  }

  /// 読み上げ中・キュー待ちの発話をすべて止める。よみれんしゅう が読み始める時に重ならないようにするために使う。
  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
  }
}
