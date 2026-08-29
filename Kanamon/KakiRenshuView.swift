import SwiftUI

/// かきれんしゅう画面だけで使う色。共通のスタイルトークンは `DesignColor` を参照する。
enum KakiRenshuColor {
  /// かき画面の地の色 (README「6. スタイルトークン」の画面ごとの地の色)
  static let background = Color(hex: 0xEAFBEE)
  /// お手本として薄く出す全画の線
  static let ghost = Color(hex: 0xE0D3BA)
  /// なぞり面の十字のガイド線
  static let guideLine = Color(hex: 0xE4D9C4)
  /// 書き終えた画の番号の地
  static let writtenNumber = Color(hex: 0xE9DFCC)
  /// 書き終えた画の番号の枠
  static let writtenNumberBorder = Color(hex: 0xBCAC90)
}

/// かきれんしゅう画面に出す固定の文言。子どもが読めるようにひらがな・カタカナだけで書く。
enum KakiRenshuText {
  static let title = "かきれんしゅう"
  static let playStrokeOrder = "かきじゅん を みる"
  static let speak = "よんで もらう"
  static let otherPokemon = "ほかの モンスター の なまえ"
  static let previousPokemon = "まえ の モンスター"
  static let nextPokemon = "つぎ の モンスター"
  static let next = "つぎ へ"
  static let caught = "ゲット！"
  static let written = "かけたね！"
  static let registered = "ずかん に とうろく したよ"
  static let notRegistered = "とうろく できなかったよ"

  /// 画面に出すすべての文言。かなだけで書けているかをテストで検証するために並べる。
  static let all: [String] = [
    title, playStrokeOrder, speak, otherPokemon, previousPokemon, nextPokemon,
    next, caught, written, registered, notRegistered,
  ]
}

/// かきれんしゅう画面。名前の文字を 1 文字ずつ、書き順の番号と進行方向の矢印に沿ってなぞる。
///
/// 失敗しても書いた画を消さず、回数制限も減点も設けない (`documents/design/README.md`「4. かきれんしゅう」)。
struct KakiRenshuView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var model = KakiRenshuModel()
  /// なぞっている最中の軌跡 (109 座標系)。
  @State private var tracePoints: [CGPoint] = []
  /// 「かきじゅん を みる」で描いている画の番号。再生していなければ nil。
  @State private var demoStrokeIndex: Int?
  /// 再生中の画をどこまで描いたか (0...1)。
  @State private var demoProgress: CGFloat = 0
  @State private var demoTask: Task<Void, Never>?

  var body: some View {
    ZStack {
      VStack(spacing: 11) {
        header
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      if let result = model.result {
        CaughtCelebrationView(result: result, imageCache: model.imageCache) {
          stopDemo()
          model.dismissResult()
        }
        .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // NavigationStack は自前の地の色 (白) を敷くため、画面ごとに塗り直す。
    // かき画面の地の色はデザイン仕様 (documents/design/README.md「6. スタイルトークン」) の #EAFBEE
    .background(KakiRenshuColor.background)
    .toolbar(.hidden, for: .navigationBar)
    .task {
      await model.load(modelContext: modelContext)
    }
    .onDisappear {
      stopDemo()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      PokedexBackButton {
        stopDemo()
        dismiss()
      }

      Text(KakiRenshuText.title)
        .font(.system(size: 30, weight: .black, design: .rounded))
        .foregroundStyle(DesignColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 64)
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .loading:
      VStack(spacing: 16) {
        ProgressView()
          .controlSize(.large)
        Text(KakiRenshuMessage.loading)
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .foregroundStyle(DesignColor.ink)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failure:
      VStack(spacing: 24) {
        Text(model.message)
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .foregroundStyle(DesignColor.ink)
          .multilineTextAlignment(.center)
        Button {
          Task {
            await model.load(modelContext: modelContext)
          }
        } label: {
          Text(KakiRenshuMessage.retry)
            .font(.system(size: 30, weight: .black, design: .rounded))
            .foregroundStyle(DesignColor.paper)
            .frame(maxWidth: .infinity, minHeight: 76)
        }
        .buttonStyle(Self.primaryButtonStyle(background: DesignColor.blue))
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .tracing:
      tracingContent
    }
  }

  private var tracingContent: some View {
    VStack(spacing: 11) {
      nameRow
      traceFace
      Text(model.message)
        .font(.system(size: 17, weight: .heavy, design: .rounded))
        .foregroundStyle(DesignColor.ink)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity)
      actionButtons
      pokemonSwitcher
      attribution
    }
  }

  private var nameRow: some View {
    HStack(spacing: 12) {
      if let currentPokemon = model.currentPokemon {
        PokemonSpriteView(pokemon: currentPokemon, isCaught: true, imageCache: model.imageCache)
          .frame(width: 56, height: 56)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
          ForEach(Array(model.characters.enumerated()), id: \.offset) { index, character in
            Button {
              stopDemo()
              model.selectCharacter(at: index)
            } label: {
              NameCharacterLabel(
                character: character,
                isCurrent: index == model.characterIndex,
                isWritten: model.isWritten(character)
              )
            }
            .buttonStyle(
              PokedexCardButtonStyle(
                background: NameCharacterLabel.background(
                  isCurrent: index == model.characterIndex,
                  isWritten: model.isWritten(character)
                ),
                cornerRadius: 12,
                borderWidth: 4,
                shadowHeight: 4
              )
            )
          }
        }
      }
      Text("\(model.characterIndex + 1) / \(max(model.characters.count, 1))")
        .font(.system(size: 15, weight: .heavy, design: .rounded))
        .foregroundStyle(DesignColor.ink)
    }
    .padding(10)
    .background(DesignColor.cream)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(DesignColor.ink, lineWidth: 5)
    )
  }

  private var traceFace: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      TraceCanvas(
        strokes: model.strokes,
        strokeIndex: model.strokeIndex,
        tracePoints: tracePoints,
        demoStrokeIndex: demoStrokeIndex,
        demoProgress: demoProgress,
        side: side,
        onTracePoint: { point in
          guard demoStrokeIndex == nil else {
            return
          }
          tracePoints.append(point)
        },
        onTraceEnd: {
          guard demoStrokeIndex == nil else {
            return
          }
          let trace = tracePoints
          tracePoints = []
          model.finishTrace(trace)
        }
      )
      .frame(width: side, height: side)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .aspectRatio(1, contentMode: .fit)
    .phaseAnimator([0.0, -9.0, 9.0, -6.0, 6.0, 0.0], trigger: model.failureCount) { view, offset in
      view.offset(x: offset)
    } animation: { _ in
      .linear(duration: 0.07)
    }
  }

  private var actionButtons: some View {
    HStack(spacing: 10) {
      Button {
        playDemo()
      } label: {
        Text(KakiRenshuText.playStrokeOrder)
          .font(.system(size: 23, weight: .black, design: .rounded))
          .foregroundStyle(DesignColor.paper)
          .frame(maxWidth: .infinity, minHeight: 76)
      }
      .buttonStyle(Self.primaryButtonStyle(background: DesignColor.blue))
      .disabled(model.strokes.isEmpty)

      Button {
        model.speakCurrentCharacter()
      } label: {
        Image(systemName: "speaker.wave.3.fill")
          .font(.system(size: 30, weight: .bold))
          .foregroundStyle(DesignColor.ink)
          .frame(width: 76, height: 76)
      }
      .buttonStyle(Self.primaryButtonStyle(background: DesignColor.yellow))
      .accessibilityLabel(KakiRenshuText.speak)
    }
  }

  private var pokemonSwitcher: some View {
    HStack {
      Button {
        stopDemo()
        model.showPokemon(offsetBy: -1)
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 24, weight: .black))
          .foregroundStyle(DesignColor.ink)
          .frame(width: 56, height: 56)
      }
      .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
      .accessibilityLabel(KakiRenshuText.previousPokemon)

      Spacer()
      Text(KakiRenshuText.otherPokemon)
        .font(.system(size: 14, weight: .heavy, design: .rounded))
        .foregroundStyle(DesignColor.sandDark)
      Spacer()

      Button {
        stopDemo()
        model.showPokemon(offsetBy: 1)
      } label: {
        Image(systemName: "chevron.right")
          .font(.system(size: 24, weight: .black))
          .foregroundStyle(DesignColor.ink)
          .frame(width: 56, height: 56)
      }
      .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
      .accessibilityLabel(KakiRenshuText.nextPokemon)
    }
  }

  /// KanjiVG は CC BY-SA 3.0 のため、書き順データの帰属を画面に出す。
  private var attribution: some View {
    // なぞり面を少しでも大きく取るため、帰属表示は 2 行に収める
    VStack(spacing: 2) {
      Text(KakiRenshuAttribution.text)
      HStack(spacing: 10) {
        Link(KakiRenshuAttribution.projectName, destination: KakiRenshuAttribution.projectURL)
        Link(KakiRenshuAttribution.licenseName, destination: KakiRenshuAttribution.licenseURL)
      }
      .underline()
    }
    .font(.system(size: 10, weight: .medium))
    .foregroundStyle(DesignColor.sandDark)
    .multilineTextAlignment(.center)
  }

  /// 確定デザインの大きいボタン (押下で 5pt 沈んで影が消える)。
  private static func primaryButtonStyle(background: Color) -> PokedexCardButtonStyle {
    PokedexCardButtonStyle(background: background, cornerRadius: 26, borderWidth: 5, shadowHeight: 7)
  }

  /// お手本の再生を止めて、なぞりを受け付けられる状態へ戻す。
  private func stopDemo() {
    demoTask?.cancel()
    demoTask = nil
    demoStrokeIndex = nil
    demoProgress = 0
  }

  private func playDemo() {
    demoTask?.cancel()
    let strokes = model.strokes
    demoTask = Task {
      for index in strokes.indices {
        let duration = max(0.36, Double(strokes[index].totalLength) * 0.013)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          demoStrokeIndex = index
          demoProgress = 0
        }
        withAnimation(.easeInOut(duration: duration)) {
          demoProgress = 1
        }
        try? await Task.sleep(for: .seconds(duration + 0.19))
        guard !Task.isCancelled else {
          return
        }
      }

      try? await Task.sleep(for: .milliseconds(420))
      guard !Task.isCancelled else {
        return
      }
      demoStrokeIndex = nil
      demoProgress = 0
    }
  }
}

/// KanjiVG (CC BY-SA 3.0) の帰属表示。ライセンス上の必須表示のため文言と URL を 1 か所にまとめる。
enum KakiRenshuAttribution {
  static let text = "かきじゅん の データ: KanjiVG (C) 2009-2011 Ulrich Apel / CC BY-SA 3.0"
  static let projectName = "kanjivg.tagaini.net"
  static let licenseName = "CC BY-SA 3.0"
  static let projectURL = URL(string: "http://kanjivg.tagaini.net")!
  static let licenseURL = URL(string: "http://creativecommons.org/licenses/by-sa/3.0/")!
}

/// 名前の文字 1 つ分の表示。今なぞっている文字を光らせ、書けた文字を緑にする。
private struct NameCharacterLabel: View {
  let character: Character
  let isCurrent: Bool
  let isWritten: Bool

  var body: some View {
    Text(String(character))
      .font(.system(size: 26, weight: .black, design: .rounded))
      .foregroundStyle(isWritten && !isCurrent ? DesignColor.paper : DesignColor.ink)
      .frame(minWidth: 40, minHeight: 46)
  }

  /// タイルの地の色。今なぞっている文字は黄色、書けた文字は緑にする。
  static func background(isCurrent: Bool, isWritten: Bool) -> Color {
    if isCurrent {
      return DesignColor.yellow
    }
    if isWritten {
      return DesignColor.green
    }

    return DesignColor.cream
  }
}

/// なぞり面。お手本・書けた画・書き順の番号・進行方向の矢印・なぞっている線を重ねて描く。
private struct TraceCanvas: View {
  let strokes: [StrokePath]
  let strokeIndex: Int
  let tracePoints: [CGPoint]
  let demoStrokeIndex: Int?
  let demoProgress: CGFloat
  let side: CGFloat
  let onTracePoint: (CGPoint) -> Void
  let onTraceEnd: () -> Void

  private var scale: CGFloat { side / StrokePath.canvasSize }

  var body: some View {
    ZStack(alignment: .topLeading) {
      DesignColor.cream

      guideGrid
      ghostStrokes
      writtenStrokes
      demoStroke
      liveTrace

      ForEach(strokes.indices, id: \.self) { index in
        StrokeNumberBadge(
          stroke: strokes[index],
          number: index + 1,
          isCurrent: index == strokeIndex,
          isWritten: index < strokeIndex,
          scale: scale
        )
      }

      if demoStrokeIndex == nil, strokes.indices.contains(strokeIndex) {
        StrokeDirectionArrow(stroke: strokes[strokeIndex], scale: scale)
          .frame(width: side, height: side, alignment: .topLeading)
      }
    }
    .frame(width: side, height: side)
    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(DesignColor.ink, lineWidth: 6)
    )
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          onTracePoint(CGPoint(x: value.location.x / scale, y: value.location.y / scale))
        }
        .onEnded { _ in
          onTraceEnd()
        }
    )
  }

  private var guideGrid: some View {
    ScaledPath(
      content: scaled(
        Path { path in
          path.move(to: CGPoint(x: 54.5, y: 4))
          path.addLine(to: CGPoint(x: 54.5, y: 105))
          path.move(to: CGPoint(x: 4, y: 54.5))
          path.addLine(to: CGPoint(x: 105, y: 54.5))
        }
      )
    )
    .stroke(KakiRenshuColor.guideLine, style: StrokeStyle(lineWidth: scale, dash: [4 * scale, 4 * scale]))
    .frame(width: side, height: side, alignment: .topLeading)
  }

  private var ghostStrokes: some View {
    ScaledPath(content: scaled(combinedPath(of: strokes)))
      .stroke(
        KakiRenshuColor.ghost,
        style: StrokeStyle(lineWidth: 5.5 * scale, lineCap: .round, lineJoin: .round)
      )
      .frame(width: side, height: side, alignment: .topLeading)
  }

  private var writtenStrokes: some View {
    ScaledPath(content: scaled(combinedPath(of: Array(strokes.prefix(strokeIndex)))))
      .stroke(
        DesignColor.ink,
        style: StrokeStyle(lineWidth: 5.5 * scale, lineCap: .round, lineJoin: .round)
      )
      .frame(width: side, height: side, alignment: .topLeading)
  }

  /// お手本の再生。書き終えた画は残したまま、今描いている画だけを長さで伸ばす。
  @ViewBuilder
  private var demoStroke: some View {
    if let demoStrokeIndex, strokes.indices.contains(demoStrokeIndex) {
      ScaledPath(content: scaled(combinedPath(of: Array(strokes.prefix(demoStrokeIndex)))))
        .stroke(
          DesignColor.blue,
          style: StrokeStyle(lineWidth: 6 * scale, lineCap: .round, lineJoin: .round)
        )
        .frame(width: side, height: side, alignment: .topLeading)
      ScaledPath(content: scaled(Path(strokes[demoStrokeIndex].cgPath)))
        .trim(from: 0, to: demoProgress)
        .stroke(
          DesignColor.blue,
          style: StrokeStyle(lineWidth: 6 * scale, lineCap: .round, lineJoin: .round)
        )
        .frame(width: side, height: side, alignment: .topLeading)
    }
  }

  @ViewBuilder
  private var liveTrace: some View {
    if tracePoints.count >= 2 {
      ScaledPath(
        content: scaled(
          Path { path in
            path.addLines(tracePoints)
          }
        )
      )
      .stroke(
        DesignColor.green.opacity(0.85),
        style: StrokeStyle(lineWidth: 7 * scale, lineCap: .round, lineJoin: .round)
      )
      .frame(width: side, height: side, alignment: .topLeading)
    }
  }

  private func combinedPath(of strokes: [StrokePath]) -> Path {
    var path = Path()
    for stroke in strokes {
      path.addPath(Path(stroke.cgPath))
    }

    return path
  }

  private func scaled(_ path: Path) -> Path {
    path.applying(CGAffineTransform(scaleX: scale, y: scale))
  }
}

/// 109 座標系で組み立て済みの図形を、置かれた場所の左上を原点にして描く。
private struct ScaledPath: Shape {
  let content: Path

  func path(in rect: CGRect) -> Path {
    content
  }
}

/// 書き順の番号。今なぞる画は黄色で脈打ち、書き終えた画は灰色にする。
private struct StrokeNumberBadge: View {
  let stroke: StrokePath
  let number: Int
  let isCurrent: Bool
  let isWritten: Bool
  let scale: CGFloat

  var body: some View {
    let center = Self.badgeCenter(of: stroke)

    Text("\(number)")
      .font(.system(size: 9 * scale, weight: .heavy, design: .rounded))
      .foregroundStyle(isWritten ? DesignColor.sandDark : DesignColor.ink)
      .frame(width: 14 * scale, height: 14 * scale)
      .background(background, in: Circle())
      .overlay(Circle().stroke(borderColor, lineWidth: 2.4 * scale))
      .phaseAnimator([1.0, 1.18]) { view, pulse in
        view.scaleEffect(isCurrent ? pulse : 1)
      } animation: { _ in
        .easeInOut(duration: 0.65)
      }
      .position(x: center.x * scale, y: center.y * scale)
  }

  private var background: Color {
    if isCurrent {
      return DesignColor.yellow
    }
    if isWritten {
      return KakiRenshuColor.writtenNumber
    }

    return .white
  }

  private var borderColor: Color {
    isWritten ? KakiRenshuColor.writtenNumberBorder : DesignColor.ink
  }

  /// 画の書き出しから、進行方向と逆に 10 ずらした位置。線と番号が重ならないようにする。
  static func badgeCenter(of stroke: StrokePath) -> CGPoint {
    let start = stroke.startPoint
    let ahead = stroke.point(atLength: min(stroke.totalLength, 9))
    let deltaX = start.x - ahead.x
    let deltaY = start.y - ahead.y
    let length = max(hypot(deltaX, deltaY), 1)

    return CGPoint(
      x: min(max(start.x + deltaX / length * 10, 8), 101),
      y: min(max(start.y + deltaY / length * 10, 8), 101)
    )
  }
}

/// 今なぞる画の上を、書き順の向きへ動き続ける矢印。終点まで行くと少し休んで始点から繰り返す。
private struct StrokeDirectionArrow: View {
  let stroke: StrokePath
  let scale: CGFloat

  /// 画の長さに比例させた 1 往復ぶんの時間。短い画でも速くなりすぎないよう下限を置く。
  private var duration: Double { max(0.9, Double(stroke.totalLength) * 0.022) }
  /// 終点で休む時間。
  private let restDuration = 0.42

  var body: some View {
    TimelineView(.animation) { context in
      let cycle = context.date.timeIntervalSinceReferenceDate
        .truncatingRemainder(dividingBy: duration + restDuration)
      let isMoving = cycle < duration
      let length = isMoving ? stroke.totalLength * CGFloat(cycle / duration) : 0
      let position = stroke.point(atLength: length)
      let angle = stroke.direction(atLength: length)
      let arrow = Self.arrowPath(at: position, angle: angle, scale: scale)

      ZStack(alignment: .topLeading) {
        ScaledPath(content: arrow).fill(DesignColor.red)
        ScaledPath(content: arrow).stroke(.white, lineWidth: 1.2 * scale)
      }
      .opacity(isMoving ? 1 : 0)
    }
  }

  private static func arrowPath(at position: CGPoint, angle: CGFloat, scale: CGFloat) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: -5.6))
    path.addLine(to: CGPoint(x: 9.4, y: 0))
    path.addLine(to: CGPoint(x: 0, y: 5.6))
    path.closeSubpath()

    let transform = CGAffineTransform(rotationAngle: angle)
      .concatenating(CGAffineTransform(translationX: position.x, y: position.y))
      .concatenating(CGAffineTransform(scaleX: scale, y: scale))
    return path.applying(transform)
  }
}

/// 名前を全部書けた時のゲット演出。ずかんへの登録を子どもに分かる形で見せる。
private struct CaughtCelebrationView: View {
  let result: KakiRenshuResult
  let imageCache: PokemonImageCache?
  let onNext: () -> Void

  @State private var isShining = false

  var body: some View {
    ZStack {
      DesignColor.ink.opacity(0.55).ignoresSafeArea()

      RaysShape()
        .fill(DesignColor.yellow.opacity(0.8))
        .rotationEffect(.degrees(isShining ? 360 : 0))
        .animation(.linear(duration: 24).repeatForever(autoreverses: false), value: isShining)
        .ignoresSafeArea()

      VStack(spacing: 16) {
        Text(result.isRegistered ? KakiRenshuText.caught : KakiRenshuText.written)
          .font(.system(size: 56, weight: .black, design: .rounded))
          .foregroundStyle(.white)
          .shadow(color: DesignColor.ink, radius: 0, x: 4, y: 4)

        PokemonSpriteView(pokemon: result.pokemon, isCaught: true, imageCache: imageCache)
          .frame(width: 180, height: 180)

        VStack(spacing: 6) {
          Text(result.pokemon.japaneseName)
            .font(.system(size: 40, weight: .black, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
          Text(result.isRegistered ? KakiRenshuText.registered : KakiRenshuText.notRegistered)
            .font(.system(size: 17, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(DesignColor.ink)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(DesignColor.cream, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(DesignColor.ink, lineWidth: 6)
        )

        Button {
          onNext()
        } label: {
          Text(KakiRenshuText.next)
            .font(.system(size: 30, weight: .black, design: .rounded))
            .foregroundStyle(DesignColor.paper)
            .frame(maxWidth: .infinity, minHeight: 76)
        }
        .buttonStyle(
          PokedexCardButtonStyle(
            background: DesignColor.red,
            cornerRadius: 26,
            borderWidth: 5,
            shadowHeight: 7
          )
        )
      }
      .padding(24)
    }
    .onAppear {
      isShining = true
    }
  }
}

/// ゲット演出の放射状の光。
private struct RaysShape: Shape {
  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = hypot(rect.width, rect.height)
    var path = Path()
    for index in 0..<12 {
      let angle = Double(index) / 12 * 2 * .pi
      let spread = 0.11
      path.move(to: center)
      path.addLine(
        to: CGPoint(
          x: center.x + cos(angle - spread) * radius,
          y: center.y + sin(angle - spread) * radius
        )
      )
      path.addLine(
        to: CGPoint(
          x: center.x + cos(angle + spread) * radius,
          y: center.y + sin(angle + spread) * radius
        )
      )
      path.closeSubpath()
    }

    return path
  }
}

#Preview {
  PokedexDeviceFrame {
    NavigationStack {
      KakiRenshuView()
    }
  }
  .modelContainer(PersistenceController(isStoredInMemoryOnly: true).container)
}
