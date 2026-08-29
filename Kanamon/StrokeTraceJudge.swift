import CoreGraphics
import Foundation

/// なぞり判定のゆるさを決める閾値。KanjiVG と同じ 109×109 の座標系で表す。
///
/// 挫折させないことを最優先にするため、閾値は大きめに取る (`documents/design/README.md`「4. かきれんしゅう」)。
struct StrokeTraceThreshold: Equatable {
  /// 書き出しの点からこの距離以内でなぞり始めていれば受理する。
  let startRadius: CGFloat
  /// 書き終わりの点からこの距離以内でなぞり終えていれば受理する。
  let endRadius: CGFloat
  /// 画の経路上の点が、なぞった軌跡からこの距離以内にあれば「通った」とみなす。
  let pathRadius: CGFloat
  /// 「通った」経路上の点の割合がこの値以上なら受理する。
  let requiredCoverage: Double
  /// 経路の通過判定に使う、画を等間隔に区切った点の数。
  let samplePointCount: Int
  /// 受理するために必要な、なぞった軌跡の点の数。誤タップを弾く。
  let minimumTracePointCount: Int

  static let standard = StrokeTraceThreshold(
    startRadius: 30,
    endRadius: 32,
    pathRadius: 26,
    requiredCoverage: 0.72,
    samplePointCount: 27,
    minimumTracePointCount: 4
  )
}

/// 指でなぞった軌跡が、その画を書き順どおりになぞれているかを判定する。
///
/// 失敗しても書いた画を消さない・減点しない前提のため、判定は成否だけを返す。
enum StrokeTraceJudge {
  static func isTraced(
    trace: [CGPoint],
    stroke: StrokePath,
    threshold: StrokeTraceThreshold = .standard
  ) -> Bool {
    coverage(of: trace, on: stroke, threshold: threshold).map { $0 >= threshold.requiredCoverage }
      ?? false
  }

  /// 画の経路上の点のうち、なぞった軌跡の近くを通った割合。始点・終点の条件を満たさない時は nil を返す。
  static func coverage(
    of trace: [CGPoint],
    on stroke: StrokePath,
    threshold: StrokeTraceThreshold = .standard
  ) -> Double? {
    guard trace.count >= threshold.minimumTracePointCount else {
      return nil
    }

    let samplePoints = stroke.points(sampleCount: threshold.samplePointCount)
    guard let firstSamplePoint = samplePoints.first, let lastSamplePoint = samplePoints.last,
      let firstTracePoint = trace.first, let lastTracePoint = trace.last
    else {
      return nil
    }
    guard isNear(firstTracePoint, firstSamplePoint, within: threshold.startRadius) else {
      return nil
    }
    guard isNear(lastTracePoint, lastSamplePoint, within: threshold.endRadius) else {
      return nil
    }

    let passedPointCount = samplePoints.filter { samplePoint in
      trace.contains { isNear($0, samplePoint, within: threshold.pathRadius) }
    }.count

    return Double(passedPointCount) / Double(samplePoints.count)
  }

  private static func isNear(_ point: CGPoint, _ other: CGPoint, within radius: CGFloat) -> Bool {
    hypot(point.x - other.x, point.y - other.y) <= radius
  }
}
