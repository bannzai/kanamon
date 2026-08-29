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

/// 五十音表を並べる時の余白と、そこから決まる 1 マスの幅。
///
/// 子ども向けの最小タップ領域 60pt (documents/design/README.md「6. スタイルトークン > 形」) を
/// 画面の狭い端末でも満たせる値にする (`MojiZukanTests` で検証する)。
enum GojuonLayout {
  /// 表のカードを画面の左右から離す幅。他の要素 (20pt) より詰めて、マスの幅を優先する
  static let cardHorizontalPadding: CGFloat = 10
  /// カードの内側の余白
  static let cardInnerPadding: CGFloat = 6
  /// マスどうしの間隔
  static let cellSpacing: CGFloat = 4

  /// 画面の幅から 1 マスの幅を求める。
  static func cellWidth(screenWidth: CGFloat) -> CGFloat {
    let columnCount = CGFloat(GojuonTable.columnCount)
    let usedWidth =
      cardHorizontalPadding * 2 + cardInnerPadding * 2 + cellSpacing * (columnCount - 1)
    return (screenWidth - usedWidth) / columnCount
  }
}
