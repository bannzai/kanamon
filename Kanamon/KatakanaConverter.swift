/// カタカナ表記を小書き文字や長音を保ったまま、ひらがなへ機械変換する。
enum KatakanaConverter {
  static func hiragana(from katakana: String) -> String {
    var convertedScalars = String.UnicodeScalarView()

    for scalar in katakana.unicodeScalars {
      if (0x30A1...0x30F6).contains(scalar.value) {
        convertedScalars.append(UnicodeScalar(scalar.value - 0x60)!)
      } else {
        convertedScalars.append(scalar)
      }
    }

    return String(convertedScalars)
  }
}
