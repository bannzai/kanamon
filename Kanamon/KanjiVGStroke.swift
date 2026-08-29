import CoreGraphics
import Foundation

/// SVG の `d` 属性を構成する描画命令。KanjiVG のかなが使う直線と 3 次ベジェだけを表す。
enum StrokePathCommand: Equatable {
  case move(to: CGPoint)
  case line(to: CGPoint)
  case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
}

/// KanjiVG の 1 画 (ストローク) を、書き順の向きを保った折れ線として表す。
///
/// 長さを指定して途中の点を引けるようにし、書き順の矢印の位置となぞり判定の基準点を同じ表現から作る。
struct StrokePath: Equatable {
  /// KanjiVG の座標系 (viewBox) の一辺。描画も判定もこの正方形を基準に行う。
  static let canvasSize: CGFloat = 109

  /// 3 次ベジェ 1 本を折れ線へ分割する数。判定の 27 点より十分細かくする。
  private static let curveSegmentCount = 32

  let commands: [StrokePathCommand]
  private let polylinePoints: [CGPoint]
  /// `polylinePoints` の先頭から各点までの距離。
  private let cumulativeLengths: [CGFloat]

  init(commands: [StrokePathCommand]) {
    self.commands = commands

    var points: [CGPoint] = []
    var lengths: [CGFloat] = []
    var current = CGPoint.zero

    func append(_ point: CGPoint) {
      if let last = points.last {
        lengths.append(lengths[lengths.count - 1] + hypot(point.x - last.x, point.y - last.y))
      } else {
        lengths.append(0)
      }
      points.append(point)
    }

    for command in commands {
      switch command {
      case .move(let point):
        // KanjiVG の 1 画は 1 本の連続した線のため、2 つ目以降の move は折れ線を切らずに繋ぐ。
        append(point)
        current = point
      case .line(let point):
        append(point)
        current = point
      case .curve(let point, let control1, let control2):
        for step in 1...Self.curveSegmentCount {
          let t = CGFloat(step) / CGFloat(Self.curveSegmentCount)
          append(Self.cubicPoint(from: current, control1: control1, control2: control2, to: point, at: t))
        }
        current = point
      }
    }

    polylinePoints = points
    cumulativeLengths = lengths
  }

  init(pathData: String) throws {
    self.init(commands: try SVGPathParser.commands(from: pathData))
  }

  var totalLength: CGFloat { cumulativeLengths.last ?? 0 }

  var startPoint: CGPoint { polylinePoints.first ?? .zero }

  var endPoint: CGPoint { polylinePoints.last ?? .zero }

  var isEmpty: Bool { polylinePoints.isEmpty }

  /// 書き出しからの距離を指定して、画の上の点を求める。範囲外の距離は両端に丸める。
  func point(atLength length: CGFloat) -> CGPoint {
    guard let first = polylinePoints.first else {
      return .zero
    }
    guard length > 0 else {
      return first
    }
    guard length < totalLength else {
      return polylinePoints[polylinePoints.count - 1]
    }

    var low = 0
    var high = cumulativeLengths.count - 1
    while low + 1 < high {
      let middle = (low + high) / 2
      if cumulativeLengths[middle] <= length {
        low = middle
      } else {
        high = middle
      }
    }

    let segmentLength = cumulativeLengths[high] - cumulativeLengths[low]
    guard segmentLength > 0 else {
      return polylinePoints[low]
    }
    let ratio = (length - cumulativeLengths[low]) / segmentLength
    let start = polylinePoints[low]
    let end = polylinePoints[high]
    return CGPoint(x: start.x + (end.x - start.x) * ratio, y: start.y + (end.y - start.y) * ratio)
  }

  /// 画の書き出しから書き終わりまでを等間隔 (長さ基準) に区切った点を返す。
  func points(sampleCount: Int) -> [CGPoint] {
    guard sampleCount > 1 else {
      return polylinePoints.isEmpty ? [] : [startPoint]
    }

    return (0..<sampleCount).map { index in
      point(atLength: totalLength * CGFloat(index) / CGFloat(sampleCount - 1))
    }
  }

  /// 画の上を進む向き (ラジアン)。矢印の回転に使う。
  func direction(atLength length: CGFloat, lookAhead: CGFloat = 1.2) -> CGFloat {
    let current = point(atLength: length)
    let ahead = point(atLength: min(totalLength, length + lookAhead))
    if current == ahead, length > 0 {
      let behind = point(atLength: max(0, length - lookAhead))
      return atan2(current.y - behind.y, current.x - behind.x)
    }

    return atan2(ahead.y - current.y, ahead.x - current.x)
  }

  var cgPath: CGPath {
    let path = CGMutablePath()
    var hasCurrentPoint = false
    for command in commands {
      switch command {
      case .move(let point):
        // 折れ線と同じく、2 つ目以降の move も線を切らずに繋ぐ。
        if hasCurrentPoint {
          path.addLine(to: point)
        } else {
          path.move(to: point)
          hasCurrentPoint = true
        }
      case .line(let point):
        if hasCurrentPoint {
          path.addLine(to: point)
        } else {
          path.move(to: point)
          hasCurrentPoint = true
        }
      case .curve(let point, let control1, let control2):
        if !hasCurrentPoint {
          path.move(to: control1)
          hasCurrentPoint = true
        }
        path.addCurve(to: point, control1: control1, control2: control2)
      }
    }

    return path
  }

  private static func cubicPoint(
    from start: CGPoint,
    control1: CGPoint,
    control2: CGPoint,
    to end: CGPoint,
    at t: CGFloat
  ) -> CGPoint {
    let oneMinusT = 1 - t
    let a = oneMinusT * oneMinusT * oneMinusT
    let b = 3 * oneMinusT * oneMinusT * t
    let c = 3 * oneMinusT * t * t
    let d = t * t * t
    return CGPoint(
      x: a * start.x + b * control1.x + c * control2.x + d * end.x,
      y: a * start.y + b * control1.y + c * control2.y + d * end.y
    )
  }
}

/// SVG の `d` 属性を描画命令へ変換する。
///
/// KanjiVG のかなは `M` と `c` だけで書かれているが、絶対・相対と滑らかな曲線の指定にも対応する。
/// 対応していない命令は黙って読み飛ばさずエラーにして、崩れた経路で判定しないようにする。
enum SVGPathParser {
  static func commands(from pathData: String) throws -> [StrokePathCommand] {
    var scanner = SVGPathDataScanner(pathData)
    var commands: [StrokePathCommand] = []
    var current = CGPoint.zero
    /// 直前の 3 次ベジェの 2 つ目の制御点。`S` / `s` の 1 つ目の制御点を鏡映で求めるために持つ。
    var previousCurveControl: CGPoint?

    while let letter = try scanner.nextCommandLetter() {
      let isRelative = letter.isLowercase
      guard let kind = SVGPathCommandKind(letter: Character(letter.lowercased())) else {
        throw SVGPathParsingError.unsupportedCommand(letter)
      }
      guard !commands.isEmpty || kind == .move else {
        throw SVGPathParsingError.missingInitialMoveCommand
      }

      var isFirstGroup = true
      repeat {
        let origin = isRelative ? current : .zero
        switch kind {
        case .move:
          let point = try scanner.nextPoint(relativeTo: origin)
          // SVG の仕様どおり、move の 2 組目以降は line として扱う。
          commands.append(isFirstGroup ? .move(to: point) : .line(to: point))
          current = point
          previousCurveControl = nil
        case .line:
          let point = try scanner.nextPoint(relativeTo: origin)
          commands.append(.line(to: point))
          current = point
          previousCurveControl = nil
        case .curve:
          let control1 = try scanner.nextPoint(relativeTo: origin)
          let control2 = try scanner.nextPoint(relativeTo: origin)
          let point = try scanner.nextPoint(relativeTo: origin)
          commands.append(.curve(to: point, control1: control1, control2: control2))
          current = point
          previousCurveControl = control2
        case .smoothCurve:
          let control1: CGPoint
          if let previousCurveControl {
            control1 = CGPoint(
              x: 2 * current.x - previousCurveControl.x,
              y: 2 * current.y - previousCurveControl.y
            )
          } else {
            control1 = current
          }
          let control2 = try scanner.nextPoint(relativeTo: origin)
          let point = try scanner.nextPoint(relativeTo: origin)
          commands.append(.curve(to: point, control1: control1, control2: control2))
          current = point
          previousCurveControl = control2
        }
        isFirstGroup = false
      } while scanner.hasMoreNumbers()
    }

    guard !commands.isEmpty else {
      throw SVGPathParsingError.missingInitialMoveCommand
    }

    return commands
  }
}

/// `d` 属性の解析に失敗した理由を表す。
enum SVGPathParsingError: Error, Equatable {
  case unsupportedCommand(Character)
  case missingInitialMoveCommand
  case invalidNumber(String)
}

/// `SVGPathParser` が扱える命令の種類。
private enum SVGPathCommandKind {
  case move
  case line
  case curve
  case smoothCurve

  init?(letter: Character) {
    switch letter {
    case "m": self = .move
    case "l": self = .line
    case "c": self = .curve
    case "s": self = .smoothCurve
    default: return nil
    }
  }
}

/// `d` 属性の文字列を、命令の文字と数値へ切り出す。
private struct SVGPathDataScanner {
  private let characters: [Character]
  private var index = 0

  init(_ pathData: String) {
    characters = Array(pathData)
  }

  mutating func nextCommandLetter() throws -> Character? {
    skipSeparators()
    guard index < characters.count else {
      return nil
    }

    let character = characters[index]
    guard character.isLetter else {
      throw SVGPathParsingError.invalidNumber(String(character))
    }

    index += 1
    return character
  }

  mutating func hasMoreNumbers() -> Bool {
    skipSeparators()
    guard index < characters.count else {
      return false
    }

    let character = characters[index]
    return Self.isASCIIDigit(character) || character == "-" || character == "+" || character == "."
  }

  mutating func nextPoint(relativeTo origin: CGPoint) throws -> CGPoint {
    let x = try nextNumber()
    let y = try nextNumber()
    return CGPoint(x: origin.x + x, y: origin.y + y)
  }

  private mutating func nextNumber() throws -> CGFloat {
    skipSeparators()
    var text = ""

    if index < characters.count, characters[index] == "-" || characters[index] == "+" {
      text.append(characters[index])
      index += 1
    }
    while index < characters.count, Self.isASCIIDigit(characters[index]) {
      text.append(characters[index])
      index += 1
    }
    if index < characters.count, characters[index] == "." {
      text.append(characters[index])
      index += 1
      while index < characters.count, Self.isASCIIDigit(characters[index]) {
        text.append(characters[index])
        index += 1
      }
    }
    if index < characters.count, characters[index] == "e" || characters[index] == "E" {
      var lookAhead = index + 1
      var exponent = String(characters[index])
      if lookAhead < characters.count, characters[lookAhead] == "-" || characters[lookAhead] == "+" {
        exponent.append(characters[lookAhead])
        lookAhead += 1
      }
      var digits = ""
      while lookAhead < characters.count, Self.isASCIIDigit(characters[lookAhead]) {
        digits.append(characters[lookAhead])
        lookAhead += 1
      }
      if !digits.isEmpty {
        text += exponent + digits
        index = lookAhead
      }
    }

    guard let value = Double(text) else {
      throw SVGPathParsingError.invalidNumber(text)
    }

    return CGFloat(value)
  }

  private mutating func skipSeparators() {
    while index < characters.count, characters[index] == " " || characters[index] == ","
      || characters[index] == "\n" || characters[index] == "\r" || characters[index] == "\t"
    {
      index += 1
    }
  }

  private static func isASCIIDigit(_ character: Character) -> Bool {
    character.isASCII && character.isNumber
  }
}

/// KanjiVG の SVG から、書き順どおりに並べた画を取り出す。
///
/// 画は `id="kvg:xxxxx-sN"` の N の順に並んでおり、その順序が書き順になる。
enum KanjiVGStrokeParser {
  static func strokes(from data: Data) throws -> [StrokePath] {
    guard let svg = String(data: data, encoding: .utf8) else {
      throw KanjiVGStrokeParsingError.invalidEncoding
    }

    return try strokes(from: svg)
  }

  static func strokes(from svg: String) throws -> [StrokePath] {
    var numberedPathData: [(order: Int, pathData: String)] = []

    for tag in matches(of: Self.pathTagExpression, in: svg) {
      guard
        let identifier = firstCapture(of: Self.identifierAttributeExpression, in: tag),
        let order = firstCapture(of: Self.strokeOrderExpression, in: identifier).flatMap(Int.init),
        let pathData = firstCapture(of: Self.pathDataAttributeExpression, in: tag)
      else {
        continue
      }

      numberedPathData.append((order, pathData))
    }

    guard !numberedPathData.isEmpty else {
      throw KanjiVGStrokeParsingError.strokeNotFound
    }

    return try numberedPathData
      .sorted { $0.order < $1.order }
      .map { try StrokePath(pathData: $0.pathData) }
  }

  private static let pathTagExpression = try! NSRegularExpression(pattern: "<path\\b[^>]*>")
  private static let identifierAttributeExpression = try! NSRegularExpression(
    pattern: "\\bid\\s*=\\s*\"([^\"]*)\""
  )
  private static let pathDataAttributeExpression = try! NSRegularExpression(
    pattern: "\\bd\\s*=\\s*\"([^\"]*)\""
  )
  private static let strokeOrderExpression = try! NSRegularExpression(pattern: "-s(\\d+)$")

  private static func matches(of expression: NSRegularExpression, in text: String) -> [String] {
    expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
      .compactMap { match in
        Range(match.range, in: text).map { String(text[$0]) }
      }
  }

  private static func firstCapture(of expression: NSRegularExpression, in text: String) -> String? {
    guard
      let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      match.numberOfRanges > 1,
      let range = Range(match.range(at: 1), in: text)
    else {
      return nil
    }

    return String(text[range])
  }
}

/// KanjiVG の SVG から画を取り出せなかった理由を表す。
enum KanjiVGStrokeParsingError: Error, Equatable {
  case invalidEncoding
  case strokeNotFound
}
