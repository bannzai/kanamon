import AVFoundation

/// カタカナ 1 文字や名前を日本語音声で読み上げる。
///
/// 読み上げ中に別の文字をタップした時は前の読み上げを止めて、押した文字の音だけが鳴るようにする。
@MainActor
final class KanaSpeechSynthesizer {
  static let shared = KanaSpeechSynthesizer()

  private let synthesizer = AVSpeechSynthesizer()

  init() {
    // マナーモードでも音が出るようにする (子どもが 1 人で使うため)。
    // setActive(true) は呼ばない。simulator の実測でオーディオデバイスの構築に 1.3 秒かかり、
    // その間メインスレッドが止まってタップ直後の画面遷移が遅れるため。再生に必要な有効化は
    // AVSpeechSynthesizer が自分で行う。
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
  }

  /// 同じ文字を続けてタップしても最新の 1 回だけが鳴るように、実行前に読み上げ中の発話を止める。
  func speak(_ text: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.85) {
    synthesizer.stopSpeaking(at: .immediate)

    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
    utterance.rate = rate
    synthesizer.speak(utterance)
  }
}
