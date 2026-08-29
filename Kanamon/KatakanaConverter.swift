import Foundation

/// カタカナ表記を小書き文字や長音を保ったまま、ひらがなへ機械変換する。
enum KatakanaConverter {
  static func hiragana(from katakana: String) -> String {
    var convertedScalars = String.UnicodeScalarView()

    for scalar in katakana.unicodeScalars {
      if (0x30A1...0x30F6).contains(scalar.value)
        || (0x30FD...0x30FE).contains(scalar.value)
      {
        convertedScalars.append(UnicodeScalar(scalar.value - 0x60)!)
      } else {
        convertedScalars.append(scalar)
      }
    }

    return String(convertedScalars)
  }
}

/// 濁点・半濁点・小書き文字を、五十音の進捗に使う基底文字へ正規化する。
enum KatakanaCharacterNormalizer {
  static func baseCharacter(from character: Character) -> Character {
    var scalars = String.UnicodeScalarView()
    for scalar in String(character).decomposedStringWithCanonicalMapping.unicodeScalars
    where scalar.value != 0x3099 && scalar.value != 0x309A {
      scalars.append(scalar)
    }

    guard let characterWithoutMarks = String(scalars).precomposedStringWithCanonicalMapping.first else {
      return character
    }

    return switch characterWithoutMarks {
    case "ァ": "ア"
    case "ィ": "イ"
    case "ゥ": "ウ"
    case "ェ": "エ"
    case "ォ": "オ"
    case "ッ": "ツ"
    case "ャ": "ヤ"
    case "ュ": "ユ"
    case "ョ": "ヨ"
    case "ヮ": "ワ"
    case "ヵ": "カ"
    case "ヶ": "ケ"
    default: characterWithoutMarks
    }
  }
}

/// 五十音表に並ぶ 46 文字を、行ごとにまとめて保持する。
///
/// もじ ずかんの表と、なまえ づくりのダミー文字の候補に使う。
/// 濁点・半濁点・小書き文字は `KatakanaCharacterNormalizer` で基底文字へ寄せてから扱う。
enum KatakanaSyllabary {
  /// 五十音表の行。空欄 (ヤ行のイ段等) は含めない。
  static let rows: [[Character]] = [
    ["ア", "イ", "ウ", "エ", "オ"],
    ["カ", "キ", "ク", "ケ", "コ"],
    ["サ", "シ", "ス", "セ", "ソ"],
    ["タ", "チ", "ツ", "テ", "ト"],
    ["ナ", "ニ", "ヌ", "ネ", "ノ"],
    ["ハ", "ヒ", "フ", "ヘ", "ホ"],
    ["マ", "ミ", "ム", "メ", "モ"],
    ["ヤ", "ユ", "ヨ"],
    ["ラ", "リ", "ル", "レ", "ロ"],
    ["ワ", "ヲ", "ン"],
  ]

  /// 五十音表の 46 文字を行の順に並べたもの。
  static let characters: [Character] = rows.flatMap { $0 }
}
