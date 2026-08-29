import AVFoundation

/// カタカナの名前や 1 文字を日本語で読み上げる。
enum KanaSpeaker {
  /// 読み上げに使う合成器。読み上げ中に解放されると音が途切れるため、アプリ全体で 1 つだけ保持する。
  @MainActor private static let synthesizer = AVSpeechSynthesizer()

  /// 読み上げる速さ。
  ///
  /// 既定値は文字を目で追いながら聞けるように標準より遅くしたもので、
  /// プロトタイプ (`documents/design/prototype.html`) が名前を 0.75 倍で読ませているのに合わせている。
  static let defaultRate = AVSpeechUtteranceDefaultSpeechRate * 0.75

  /// 読み上げ中の音を止めて、渡した文字列を読み直す。
  ///
  /// 同じ文字列で何度呼んでも同じ音が鳴る (冪等)。空文字なら何もしない。
  @MainActor
  static func speak(text: String, rate: Float = defaultRate) {
    guard !text.isEmpty else {
      return
    }

    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
    utterance.rate = rate
    synthesizer.speak(utterance)
  }
}
