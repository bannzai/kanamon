import SwiftUI
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

  func testViewsCanBeInstantiated() {
    XCTAssertNotNil(HomeView().body)
    for item in HomeMenuItem.all {
      XCTAssertNotNil(PlaceholderView(title: item.title).body)
    }
  }
}

extension String {
  /// ひらがな (U+3041-U+309F) とカタカナ (U+30A0-U+30FF。長音符「ー」を含む) だけで構成されているか。
  fileprivate var isKanaOnly: Bool {
    unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) || (0x30A0...0x30FF).contains($0.value) }
  }
}
