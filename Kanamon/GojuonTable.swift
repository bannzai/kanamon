import Foundation

/// もじ ずかんで五十音を並べる 5 列 10 行の表の形。ヤ行・ワ行の空きマスは nil で表す。
///
/// 並べる 46 文字そのものは `KatakanaGojuon` を正とし、ここは配置だけを持つ
/// (一致は `MojiZukanTests` で検証する)。
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
}
