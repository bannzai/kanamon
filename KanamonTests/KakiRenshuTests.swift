import CoreGraphics
import XCTest

@testable import Kanamon

/// かきれんしゅうの書き順データ解析となぞり判定を検証する。
///
/// KanjiVG のデータはリポジトリに置かないため (`documents/adr/0001-...`、issue #19 の実行時取得の決定)、
/// テストは実在の書き順データではなく、この場で組み立てた経路を使う。
final class KakiRenshuTests: XCTestCase {
  // MARK: - d 属性の解析

  func testSVGPathParserReadsAbsoluteMoveAndRelativeCurve() throws {
    let commands = try SVGPathParser.commands(from: "M10,20c5,0 10,5 10,10")

    XCTAssertEqual(
      commands,
      [
        .move(to: CGPoint(x: 10, y: 20)),
        .curve(
          to: CGPoint(x: 20, y: 30),
          control1: CGPoint(x: 15, y: 20),
          control2: CGPoint(x: 20, y: 25)
        ),
      ]
    )
  }

  func testSVGPathParserRepeatsCommandForFollowingArgumentGroups() throws {
    let commands = try SVGPathParser.commands(from: "M0,0 L10,0 20,0")

    XCTAssertEqual(
      commands,
      [.move(to: .zero), .line(to: CGPoint(x: 10, y: 0)), .line(to: CGPoint(x: 20, y: 0))]
    )
  }

  func testSVGPathParserTreatsSecondMovePairAsLine() throws {
    let commands = try SVGPathParser.commands(from: "M0,0 5,0")

    XCTAssertEqual(commands, [.move(to: .zero), .line(to: CGPoint(x: 5, y: 0))])
  }

  func testSVGPathParserReflectsPreviousControlPointForSmoothCurve() throws {
    let commands = try SVGPathParser.commands(from: "M0,0C0,10 10,10 10,0S20,-10 20,0")

    XCTAssertEqual(
      commands,
      [
        .move(to: .zero),
        .curve(
          to: CGPoint(x: 10, y: 0),
          control1: CGPoint(x: 0, y: 10),
          control2: CGPoint(x: 10, y: 10)
        ),
        .curve(
          to: CGPoint(x: 20, y: 0),
          control1: CGPoint(x: 10, y: -10),
          control2: CGPoint(x: 20, y: -10)
        ),
      ]
    )
  }

  func testSVGPathParserReadsNumbersWithoutSeparatorBeforeMinus() throws {
    let commands = try SVGPathParser.commands(from: "M10-20l-5-5")

    XCTAssertEqual(
      commands,
      [.move(to: CGPoint(x: 10, y: -20)), .line(to: CGPoint(x: 5, y: -25))]
    )
  }

  func testSVGPathParserRejectsUnsupportedCommandInsteadOfSkippingIt() {
    XCTAssertThrowsError(try SVGPathParser.commands(from: "M0,0A10,10 0 0 1 10,10")) { error in
      XCTAssertEqual(error as? SVGPathParsingError, .unsupportedCommand("A"))
    }
  }

  func testSVGPathParserRejectsPathWithoutInitialMove() {
    XCTAssertThrowsError(try SVGPathParser.commands(from: "L10,10")) { error in
      XCTAssertEqual(error as? SVGPathParsingError, .missingInitialMoveCommand)
    }
  }

  // MARK: - 画の長さと点の取り出し

  func testStrokePathMeasuresLengthAlongPolyline() throws {
    let stroke = try StrokePath(pathData: "M0,0 L30,0 L30,40")

    XCTAssertEqual(stroke.totalLength, 70, accuracy: 0.001)
    XCTAssertEqual(stroke.startPoint, .zero)
    XCTAssertEqual(stroke.endPoint, CGPoint(x: 30, y: 40))
  }

  func testStrokePathSamplesPointsEvenlyByLength() throws {
    let stroke = try StrokePath(pathData: "M0,0 L100,0")
    let points = stroke.points(sampleCount: 27)

    XCTAssertEqual(points.count, 27)
    XCTAssertEqual(points[0].x, 0, accuracy: 0.001)
    XCTAssertEqual(points[13].x, 50, accuracy: 0.001)
    XCTAssertEqual(points[26].x, 100, accuracy: 0.001)
  }

  func testStrokePathReturnsDirectionAlongWritingOrder() throws {
    let stroke = try StrokePath(pathData: "M0,0 L0,50")

    XCTAssertEqual(stroke.direction(atLength: 10), .pi / 2, accuracy: 0.01)
  }

  func testStrokePathClampsLengthOutsideThePath() throws {
    let stroke = try StrokePath(pathData: "M0,0 L100,0")

    XCTAssertEqual(stroke.point(atLength: -10), .zero)
    XCTAssertEqual(stroke.point(atLength: 500), CGPoint(x: 100, y: 0))
  }

  // MARK: - KanjiVG の SVG からの取り出し

  func testKanjiVGStrokeParserOrdersStrokesByWritingOrderNumber() throws {
    let strokes = try KanjiVGStrokeParser.strokes(from: Self.svg)

    XCTAssertEqual(strokes.count, 2)
    XCTAssertEqual(strokes[0].startPoint, CGPoint(x: 10, y: 10))
    XCTAssertEqual(strokes[1].startPoint, CGPoint(x: 20, y: 20))
  }

  func testKanjiVGStrokeParserIgnoresPathsWithoutStrokeOrderIdentifier() throws {
    let strokes = try KanjiVGStrokeParser.strokes(
      from: """
        <svg>
        <path id="kvg:00061-s1" d="M0,0 L10,0"/>
        <path id="kvg:StrokeNumbers_00061" d="M50,50 L60,60"/>
        <path d="M70,70 L80,80"/>
        </svg>
        """
    )

    XCTAssertEqual(strokes.count, 1)
  }

  func testKanjiVGStrokeParserReportsMissingStrokes() {
    XCTAssertThrowsError(try KanjiVGStrokeParser.strokes(from: "<svg></svg>")) { error in
      XCTAssertEqual(error as? KanjiVGStrokeParsingError, .strokeNotFound)
    }
  }

  // MARK: - なぞり判定

  func testStrokeTraceJudgeAcceptsTraceAlongTheStroke() throws {
    let stroke = try StrokePath(pathData: "M20,20 L90,20")
    let trace = stroke.points(sampleCount: 40)

    XCTAssertTrue(StrokeTraceJudge.isTraced(trace: trace, stroke: stroke))
  }

  /// 子どもの指はぶれるため、少しずれた軌跡でも受理する。
  func testStrokeTraceJudgeAcceptsSlightlyShiftedTrace() throws {
    let stroke = try StrokePath(pathData: "M20,20 L90,20")
    let trace = stroke.points(sampleCount: 40).enumerated().map { index, point in
      CGPoint(x: point.x, y: point.y + (index % 2 == 0 ? 8 : -8))
    }

    XCTAssertTrue(StrokeTraceJudge.isTraced(trace: trace, stroke: stroke))
  }

  func testStrokeTraceJudgeRejectsTraceStartedFarFromTheStrokeStart() throws {
    let stroke = try StrokePath(pathData: "M20,20 L90,20")
    // 書き終わりから書き出しへ向かう、向きが逆の軌跡
    let trace = stroke.points(sampleCount: 40).reversed()

    XCTAssertFalse(StrokeTraceJudge.isTraced(trace: Array(trace), stroke: stroke))
  }

  func testStrokeTraceJudgeRejectsTraceOnACompletelyDifferentPath() throws {
    let stroke = try StrokePath(pathData: "M20,20 L90,20")
    let trace = (0...40).map { step in
      CGPoint(x: 20 + Double(step) * 70 / 40, y: 100)
    }

    XCTAssertFalse(StrokeTraceJudge.isTraced(trace: trace, stroke: stroke))
  }

  /// 画の途中で止めた軌跡は、書き終わりまで届いていないため受理しない。
  func testStrokeTraceJudgeRejectsTraceStoppedInTheMiddle() throws {
    let stroke = try StrokePath(pathData: "M20,20 L90,20")
    let trace = stroke.points(sampleCount: 40).prefix(20)

    XCTAssertFalse(StrokeTraceJudge.isTraced(trace: Array(trace), stroke: stroke))
  }

  func testStrokeTraceJudgeRejectsTapWithTooFewPoints() throws {
    let stroke = try StrokePath(pathData: "M20,20 L90,20")

    XCTAssertFalse(
      StrokeTraceJudge.isTraced(trace: [CGPoint(x: 20, y: 20), CGPoint(x: 90, y: 20)], stroke: stroke)
    )
  }

  func testStrokeTraceThresholdMatchesTheDesignSpecification() {
    let threshold = StrokeTraceThreshold.standard

    XCTAssertEqual(threshold.startRadius, 30)
    XCTAssertEqual(threshold.endRadius, 32)
    XCTAssertEqual(threshold.pathRadius, 26)
    XCTAssertEqual(threshold.requiredCoverage, 0.72)
    XCTAssertEqual(threshold.samplePointCount, 27)
  }

  // MARK: - 画面

  func testKakiRenshuIsReachableFromHome() {
    XCTAssertTrue(AppDestination.allCases.contains(.kakiRenshu))
    XCTAssertEqual(HomeMenuItem(destination: .kakiRenshu).title, "かきれんしゅう")
  }

  /// KanjiVG は CC BY-SA 3.0 のため、書き順データの帰属表示を画面に出す (issue #19 の決定)。
  func testKakiRenshuShowsKanjiVGAttribution() {
    XCTAssertTrue(KakiRenshuAttribution.text.contains("KanjiVG"))
    XCTAssertTrue(KakiRenshuAttribution.text.contains("Ulrich Apel"))
    XCTAssertTrue(KakiRenshuAttribution.text.contains("CC BY-SA 3.0"))
    XCTAssertEqual(KakiRenshuAttribution.projectURL.absoluteString, "http://kanjivg.tagaini.net")
    XCTAssertEqual(
      KakiRenshuAttribution.licenseURL.absoluteString,
      "http://creativecommons.org/licenses/by-sa/3.0/"
    )
  }

  @MainActor
  func testKakiRenshuViewCanBeInstantiated() {
    XCTAssertNotNil(KakiRenshuView().body)
  }

  /// 書き順データを取れない文字 (ニドラン♀ の「♀」等) では、なぞりを始めずに案内を出す。
  @MainActor
  func testKakiRenshuModelStartsWithLoadingMessage() {
    let model = KakiRenshuModel(strokeCache: nil)

    XCTAssertEqual(model.phase, .loading)
    XCTAssertTrue(model.strokes.isEmpty)
    XCTAssertTrue(model.characters.isEmpty)
  }

  /// 書き順データが 2 画ぶん並んでいる、KanjiVG と同じ形の SVG。
  private static let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="109" height="109" viewBox="0 0 109 109">
    <g id="kvg:StrokePaths_00061">
    <path id="kvg:00061-s2" kvg:type="\\u3042" d="M20,20c5,0 10,5 10,10"/>
    <path id="kvg:00061-s1" d="M10,10c5,0 10,5 10,10"/>
    </g>
    </svg>
    """
}
