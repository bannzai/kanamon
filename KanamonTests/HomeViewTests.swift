import SwiftUI
import UIKit
import XCTest

@testable import Kanamon

final class HomeViewTests: XCTestCase {
  func testHomeMenuCoversAllDestinations() {
    XCTAssertEqual(HomeMenuItem.all.map(\.destination), AppDestination.allCases)
  }

  func testHomeMenuTitlesAreUnique() {
    let titles = HomeMenuItem.all.map(\.title)
    XCTAssertEqual(Set(titles).count, titles.count)
  }

  /// 子どもが読めるように、画面に出す文言はひらがな・カタカナだけにする。
  func testHomeMenuTitlesUseOnlyKana() {
    for item in HomeMenuItem.all {
      XCTAssertTrue(item.title.isKanaOnly, "\(item.title) にひらがな・カタカナ以外の文字が含まれている")
    }
  }

  func testPlaceholderTitleUsesOnlyKana() {
    XCTAssertTrue("じゅんびちゅう".isKanaOnly)
    XCTAssertTrue("もどる".isKanaOnly)
    XCTAssertTrue("カナモン".isKanaOnly)
  }

  /// ボタンの白文字が読めるように、背景色とのコントラスト比を WCAG の通常文字の基準 4.5:1 以上にする。
  func testHomeMenuTintsHaveEnoughContrastAgainstWhiteLabel() {
    for item in HomeMenuItem.all {
      let ratio = UIColor(item.tint).contrastRatioAgainstWhite
      XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(item.title) のコントラスト比が \(ratio) しかない")
    }
  }

  func testViewsCanBeInstantiated() {
    XCTAssertNotNil(HomeView().body)
    for item in HomeMenuItem.all {
      XCTAssertNotNil(PlaceholderView(title: item.title).body)
    }
  }
}

extension String {
  /// ひらがな (U+3041-U+309F) とカタカナ (U+30A0-U+30FF。長音符「ー」を含む)、
  /// および分かち書きの半角空白だけで構成されているか。
  ///
  /// 空白を許すのは、まだ単語の切れ目が分からない子ども向けに文言を分かち書きするため
  /// (documents/design/README.md の文言がすべて分かち書きになっている)。
  fileprivate var isKanaOnly: Bool {
    unicodeScalars.allSatisfy {
      (0x3041...0x309F).contains($0.value) || (0x30A0...0x30FF).contains($0.value) || $0.value == 0x20
    }
  }
}

extension UIColor {
  /// 白 (#FFFFFF) を前景に置いた時の WCAG コントラスト比。
  fileprivate var contrastRatioAgainstWhite: CGFloat {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    getRed(&red, green: &green, blue: &blue, alpha: &alpha)

    func linear(_ component: CGFloat) -> CGFloat {
      component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    return 1.05 / (luminance + 0.05)
  }
}
