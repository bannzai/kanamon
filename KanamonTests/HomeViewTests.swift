import SwiftUI
import UIKit
import XCTest

@testable import Kanamon

final class HomeViewTests: XCTestCase {
  func testHomeMenuCoversAllDestinations() {
    XCTAssertEqual(HomeMenuItem.all.map(\.destination), AppDestination.allCases)
  }

  /// 確定デザイン (documents/design/README.md「2. 画面一覧と遷移」) の並び順どおりに導線を出す。
  func testHomeMenuOrderFollowsDesign() {
    XCTAssertEqual(
      HomeMenuItem.all.map(\.title),
      ["ずかん", "よみれんしゅう", "かきれんしゅう", "クイズ", "なまえ づくり", "もじ ずかん"]
    )
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

  func testHomeTextsUseOnlyKana() {
    let progress = HomeProgress(caughtPokemonCount: 3, readCharacterCount: 12)
    for destination in AppDestination.allCases {
      let description = HomeText.description(destination: destination, progress: progress)
      XCTAssertTrue(description.isKanaOnly, "\(description) にひらがな・カタカナ以外の文字が含まれている")
    }

    XCTAssertTrue(HomeText.title.isKanaOnly)
    XCTAssertTrue(HomeText.subtitle.isKanaOnly)
    XCTAssertTrue("じゅんびちゅう".isKanaOnly)
    XCTAssertTrue(PokedexDeviceText.title.isKanaOnly)
    XCTAssertTrue(PokedexDeviceText.back.isKanaOnly)
  }

  /// 進捗の数はホームの説明文とピルにそのまま出す。
  func testHomeProgressTexts() {
    let progress = HomeProgress(caughtPokemonCount: 3, readCharacterCount: 12)

    XCTAssertEqual(progress.caughtCountText, "3 / 151")
    XCTAssertEqual(
      HomeText.description(destination: .zukan, progress: progress),
      "あつめた モンスター 3 ひき"
    )
    XCTAssertEqual(
      HomeText.description(destination: .mojiZukan, progress: progress),
      "よめた もじ 12 / 46"
    )
  }

  /// もじ ずかんの分母は五十音の 46 文字にする (documents/design/README.md「3. もじ ずかん」)。
  func testGojuonHas46Characters() {
    XCTAssertEqual(KatakanaGojuon.characters.count, 46)
    XCTAssertEqual(KatakanaGojuon.characterSet.count, 46)
  }

  /// 確定デザインの配色をそのまま実装しているか、色の値で確認する。
  func testHomeMenuColorsFollowDesign() {
    let expectedTints: [AppDestination: Color] = [
      .zukan: DesignColor.yellow,
      .yomiRenshu: DesignColor.blue,
      .kakiRenshu: DesignColor.green,
      .quiz: DesignColor.red,
      .namaeZukuri: DesignColor.purple,
      .mojiZukan: DesignColor.pink,
    ]

    for item in HomeMenuItem.all {
      XCTAssertEqual(
        UIColor(item.tint).rgbComponents,
        UIColor(expectedTints[item.destination]!).rgbComponents,
        "\(item.title) の背景色が仕様と違う"
      )
    }
  }

  /// インクの文字を載せるボタン (黄・ピンク) は WCAG の 4.5:1 を満たすことを確認する。
  ///
  /// 白文字のボタン (青・緑・赤・紫) は確定デザインの配色をそのまま使っており 4.5:1 に届かないため、
  /// ここでは比を検証しない。配色そのものは `testHomeMenuColorsFollowDesign` で仕様と突き合わせる。
  func testInkLabelsHaveEnoughContrast() {
    let inkItems = HomeMenuItem.all.filter {
      UIColor($0.labelColor).rgbComponents == UIColor(DesignColor.ink).rgbComponents
    }
    XCTAssertEqual(inkItems.map(\.title), ["ずかん", "もじ ずかん"])

    for item in inkItems {
      let ratio = UIColor(item.labelColor).contrastRatio(against: UIColor(item.tint))
      XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(item.title) のインク文字のコントラスト比が \(ratio) しかない")
    }
  }

  func testViewsCanBeInstantiated() {
    XCTAssertNotNil(HomeView().body)
    XCTAssertNotNil(ContentView().body)
    for item in HomeMenuItem.all {
      XCTAssertNotNil(PlaceholderView(title: item.title).body)
    }
  }
}

extension String {
  /// ひらがな (U+3041-U+309F) とカタカナ (U+30A0-U+30FF。長音符「ー」を含む) だけで構成されているか。
  /// 「なまえ づくり」のように単語を分かち書きするため、半角空白・改行・算用数字・区切りのスラッシュも許す。
  fileprivate var isKanaOnly: Bool {
    unicodeScalars.allSatisfy { scalar in
      (0x3041...0x309F).contains(scalar.value)
        || (0x30A0...0x30FF).contains(scalar.value)
        || (0x0030...0x0039).contains(scalar.value)
        || scalar.value == 0x0020
        || scalar.value == 0x000A
        || scalar.value == 0x002F
    }
  }
}

extension UIColor {
  /// 赤・緑・青の成分。仕様の色と一致するかを比べるために使う。
  fileprivate var rgbComponents: [CGFloat] {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return [red, green, blue]
  }

  /// 2 色の WCAG コントラスト比。
  fileprivate func contrastRatio(against other: UIColor) -> CGFloat {
    let luminances = [relativeLuminance, other.relativeLuminance].sorted()
    return (luminances[1] + 0.05) / (luminances[0] + 0.05)
  }

  /// WCAG の相対輝度。
  fileprivate var relativeLuminance: CGFloat {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    getRed(&red, green: &green, blue: &blue, alpha: &alpha)

    func linear(_ component: CGFloat) -> CGFloat {
      component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }
}
