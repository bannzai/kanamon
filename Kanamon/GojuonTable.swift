import Foundation

/// もじ ずかんに並べる五十音表。5 列 10 行で、ヤ行・ワ行の空きマスは nil で表す。
///
/// 濁点・半濁点・小書き文字は表に並べず、`KatakanaCharacterNormalizer` で
/// 基底文字へまとめてから進捗として数える。
enum GojuonTable {
  /// 表の列数。デザイン仕様 (documents/design/README.md「3. もじ ずかん」) の 5 列に合わせる。
  static let columnCount = 5

  static let rows: [[Character?]] = [
    ["ア", "イ", "ウ", "エ", "オ"],
    ["カ", "キ", "ク", "ケ", "コ"],
    ["サ", "シ", "ス", "セ", "ソ"],
    ["タ", "チ", "ツ", "テ", "ト"],
    ["ナ", "ニ", "ヌ", "ネ", "ノ"],
    ["ハ", "ヒ", "フ", "ヘ", "ホ"],
    ["マ", "ミ", "ム", "メ", "モ"],
    ["ヤ", nil, "ユ", nil, "ヨ"],
    ["ラ", "リ", "ル", "レ", "ロ"],
    ["ワ", nil, "ヲ", nil, "ン"],
  ]

  /// 表の並び順のまま 1 次元にしたマス。空きマスは nil。
  static let cells: [Character?] = rows.flatMap { $0 }

  /// 進捗の分母になる 46 文字。
  static let characters: [Character] = cells.compactMap { $0 }

  /// 読めた文字のうち、五十音表に並ぶ 46 文字に入っているものを数える。
  ///
  /// 長音符「ー」のように表へ並べていない文字は分子に含めない。
  static func readCount(readCharacters: Set<Character>) -> Int {
    characters.filter(readCharacters.contains).count
  }
}
