import SwiftUI

/// 確定デザイン (documents/design/README.md「6. スタイルトークン」) の色。
/// 値は README の 16 進表記をそのまま持ち、画面側はここから参照する。
enum DesignColor {
  /// インク (文字・枠)
  static let ink = Color(hex: 0x33241A)
  /// クリーム (背景)
  static let cream = Color(hex: 0xFFF6E3)
  /// カード・ボタンの白地
  static let paper = Color.white
  /// 図鑑の赤
  static let red = Color(hex: 0xD93B2B)
  static let redLight = Color(hex: 0xF4634F)
  static let redDark = Color(hex: 0xA62A1D)
  /// 図鑑筐体の下方向の厚み影
  static let deviceShadow = Color(hex: 0x7A1D13)
  /// はめ込み画面のインナーシャドウ (薄赤)
  static let screenInset = Color(hex: 0xF7D9D2)
  /// 黄 (ずかん・ごほうび)
  static let yellow = Color(hex: 0xFFC22E)
  /// 青 (よみ・選択中)
  static let blue = Color(hex: 0x2BA9FF)
  /// 緑 (かき・正解・進捗)
  static let green = Color(hex: 0x4CC66A)
  /// ピンク (もじずかん・さし色)
  static let pink = Color(hex: 0xFF9FC4)
  /// 砂 (未ゲットの背景)
  static let sand = Color(hex: 0xF0E3C9)
  /// 砂の上の文字
  static let sandDark = Color(hex: 0xA8977A)
  /// 砂の枠と影
  static let sandBorder = Color(hex: 0xC8B698)
  /// 筐体の赤ランプ
  static let lampRed = Color(hex: 0xFF5A3C)
  /// 筐体のレンズ (明・中・暗) とリング
  static let lensLight = Color(hex: 0xBFE9FF)
  static let lensMiddle = Color(hex: 0x4FB8FF)
  static let lensDark = Color(hex: 0x1668B0)
  static let lensRing = Color(hex: 0xEAF6FF)
}

extension Color {
  /// README の 16 進表記 (例: 0x33241A) をそのまま書けるようにするための init。
  /// デザイン仕様との突き合わせを 1 対 1 にするためで、10 進の RGB へ手で換算しない。
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}
