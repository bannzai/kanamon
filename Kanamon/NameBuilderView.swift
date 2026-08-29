import SwiftUI

/// なまえ づくり画面に出す文言。子どもが読めるようにひらがな・カタカナ・数字だけで書く。
enum NameBuilderText {
  static let title = "なまえづくり"
  static let prompt = "もじ を えらんで なまえ に しよう"
  static let undo = "1つ もどす"
  static let speak = "よんで もらう"
  static let next = "つぎ へ"
  static let tryAgain = "もう いちど"
  static let getHeadline = "ゲット！"
  static let correctHeadline = "せいかい！"
  static let registered = "ずかん に とうろく したよ"
  static let alreadyRegistered = "なまえ を つくれたね"
  static let loading = "よみこみちゅう"
  static let failed = "よみこめなかったよ"
  static let retry = "もういちど"

  /// 画面に出すすべての文言。かなだけで書けているかをテストで検証するために並べる。
  static let all: [String] = [
    title, prompt, undo, speak, next, tryAgain, getHeadline, correctHeadline,
    registered, alreadyRegistered, loading, failed, retry,
  ]
}

/// なまえ づくり画面のデザイントークン。共通の色は `DesignColor` を使い、この画面だけの色をここに置く。
enum NameBuilderColor {
  /// 画面の地の色。
  static let background = Color(hex: 0xF3EEFF)
  /// 空きマスの地の色と破線の枠。
  static let slot = Color(hex: 0xF6F1FF)
  static let slotBorder = Color(hex: 0xB7A6E0)
  /// カタカナの下に添えるひらがなの色。
  static let hiragana = Color(hex: 0x1F7FC4)
}

/// 絵を見て文字タイルを 1 つずつ選び、名前を組み立てる画面。
///
/// デザインは `documents/design/README.md`「4-2. なまえ づくり」に従う。
struct NameBuilderView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var model: NameBuilderModel?

  var body: some View {
    ZStack {
      NameBuilderColor.background.ignoresSafeArea()
      if let model {
        NameBuilderContentView(model: model)
      } else {
        NameBuilderStatusView(text: NameBuilderText.loading) { ProgressView() }
      }
    }
    .navigationTitle(NameBuilderText.title)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      guard model == nil else {
        return
      }
      let model = NameBuilderModel(modelContext: modelContext)
      self.model = model
      await model.load()
    }
  }
}

/// `NameBuilderModel` の状態を実際に描く画面本体。
private struct NameBuilderContentView: View {
  let model: NameBuilderModel

  /// 正解した時に先頭から緑へ光らせたマスの数。
  @State private var litSlotCount = 0
  /// 間違えた時にマスを揺らすための回数。増やすたびに 1 往復ぶん揺れる。
  @State private var shakeCount = 0
  @State private var overlay = false

  var body: some View {
    ZStack {
      switch model.state {
      case .loading:
        NameBuilderStatusView(text: NameBuilderText.loading) { ProgressView() }
      case .failed:
        NameBuilderStatusView(text: NameBuilderText.failed) {
          Button(NameBuilderText.retry) {
            Task { await model.retryLoad() }
          }
          .font(.system(size: 26, weight: .heavy, design: .rounded))
          .foregroundStyle(DesignColor.ink)
        }
      case .loaded:
        if let pokemon = model.pokemon, let game = model.game {
          board(pokemon: pokemon, game: game)
        }
      }

      if overlay, let result = model.result {
        NameBuilderGetOverlay(result: result, imageCache: model.imageCache) {
          overlay = false
          litSlotCount = 0
          model.advance()
        }
      }
    }
  }

  private func board(pokemon: Pokemon, game: NameBuilderGame) -> some View {
    VStack(spacing: 12) {
      QuizSpriteImage(pokemon: pokemon, imageCache: model.imageCache, size: 178)
        .frame(maxWidth: .infinity, minHeight: 196)
        .background(DesignColor.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(DesignColor.ink, lineWidth: 5)
        }

      Text(NameBuilderText.prompt)
        .font(.system(size: 19, weight: .heavy, design: .rounded))
        .foregroundStyle(DesignColor.ink)

      NameBuilderCard {
        WrappingRows(spacing: 7) {
          ForEach(0..<game.answer.count, id: \.self) { index in
            NameBuilderSlot(
              character: index < game.placed.count ? game.placed[index] : nil,
              isLit: index < litSlotCount
            )
            .onTapGesture {
              model.removePlaced(index: index)
            }
          }
        }
        .modifier(ShakeEffect(shakeCount: CGFloat(shakeCount)))
      }

      NameBuilderCard {
        WrappingRows(spacing: 8) {
          ForEach(game.tileStates) { tile in
            NameBuilderTileView(tile: tile)
              .onTapGesture {
                tap(tile: tile)
              }
          }
        }
      }

      HStack(spacing: 10) {
        NameBuilderActionButton(
          title: NameBuilderText.undo,
          systemImage: "arrow.uturn.backward",
          tint: DesignColor.yellow,
          foreground: DesignColor.ink
        ) {
          model.undo()
        }

        NameBuilderActionButton(
          title: NameBuilderText.speak,
          systemImage: "speaker.wave.3.fill",
          tint: DesignColor.blue,
          foreground: .white
        ) {
          SpeechSynthesizer.shared.speak(pokemon.japaneseName)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: 520)
  }

  private func tap(tile: NameBuilderGame.Tile) {
    SpeechSynthesizer.shared.speak(String(tile.character))
    switch model.place(tile: tile) {
    case .correct:
      Task { await lightSlots() }
    case .rollback(let keepCount):
      Task { await promptRetry(keepCount: keepCount) }
    case nil:
      break
    }
  }

  /// 正解したマスを先頭から順に緑へ光らせてから、ゲット演出を出す。
  private func lightSlots() async {
    guard let game = model.game else {
      return
    }

    for slotIndex in game.answer.indices {
      withAnimation(.easeOut(duration: 0.2)) {
        litSlotCount = slotIndex + 1
      }
      // 先頭から 1 マスずつ光らせて読む順序を示すため、プロトタイプと同じ 90ms 間隔にする。
      try? await Task.sleep(for: .milliseconds(90))
      guard !Task.isCancelled else {
        return
      }
    }

    if let pokemon = model.pokemon {
      SpeechSynthesizer.shared.speak(pokemon.japaneseName)
    }
    try? await Task.sleep(for: .milliseconds(480))
    guard !Task.isCancelled else {
      return
    }
    overlay = true
  }

  /// 間違いを知らせてから、先頭の合っている位置まで戻す。減点や失敗の表示はしない。
  private func promptRetry(keepCount: Int) async {
    SpeechSynthesizer.shared.speak(NameBuilderText.tryAgain)
    withAnimation(.easeInOut(duration: 0.38)) {
      shakeCount += 1
    }

    // 揺れが終わってから戻すと、どこまで合っていたかを子どもが見て分かる。
    try? await Task.sleep(for: .milliseconds(420))
    guard !Task.isCancelled else {
      return
    }
    model.rollback(keepCount: keepCount)
  }
}

/// 読み込み中・読み込み失敗を伝える表示。
private struct NameBuilderStatusView<Accessory: View>: View {
  let text: String
  @ViewBuilder let accessory: Accessory

  var body: some View {
    VStack(spacing: 20) {
      accessory
      Text(text)
        .font(.system(size: 22, weight: .heavy, design: .rounded))
        .foregroundStyle(DesignColor.ink)
    }
    .padding(24)
  }
}

/// 画面の中身を白いカードに載せる枠。太い枠とずらした影で図鑑らしい見た目にする。
private struct NameBuilderCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .padding(.horizontal, 10)
      .background(DesignColor.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .strokeBorder(DesignColor.ink, lineWidth: 5)
      }
  }
}

/// 名前の 1 文字ぶんの空きマス。埋まると白地になり、正解すると緑に光る。
private struct NameBuilderSlot: View {
  let character: Character?
  let isLit: Bool

  var body: some View {
    VStack(spacing: 2) {
      Text(character.map { String($0) } ?? " ")
        .font(.system(size: 29, weight: .heavy, design: .rounded))
        .foregroundStyle(isLit ? .white : DesignColor.ink)
      Text(character.map { KatakanaConverter.hiragana(from: String($0)) } ?? " ")
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundStyle(isLit ? .white : NameBuilderColor.hiragana)
    }
    .frame(width: 56, height: 62)
    .background(background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 15, style: .continuous)
        .strokeBorder(
          character == nil ? NameBuilderColor.slotBorder : DesignColor.ink,
          style: StrokeStyle(lineWidth: 4, dash: character == nil ? [7, 6] : [])
        )
    }
  }

  private var background: Color {
    if isLit {
      DesignColor.green
    } else if character == nil {
      NameBuilderColor.slot
    } else {
      DesignColor.paper
    }
  }
}

/// 下に並べる文字タイル。使い切ったタイルは薄くして押せないことを示す。
private struct NameBuilderTileView: View {
  let tile: NameBuilderGame.Tile

  var body: some View {
    VStack(spacing: 2) {
      Text(String(tile.character))
        .font(.system(size: 30, weight: .heavy, design: .rounded))
        .foregroundStyle(DesignColor.ink)
      Text(KatakanaConverter.hiragana(from: String(tile.character)))
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundStyle(NameBuilderColor.hiragana)
    }
    .frame(width: 60, height: 64)
    .background(DesignColor.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(DesignColor.ink, lineWidth: 4)
    }
    .opacity(tile.isSpent ? 0.26 : 1)
    .allowsHitTesting(!tile.isSpent)
  }
}

/// 画面の下に置く大きなボタン。子どもの指でも押せるように高さを 84pt にする (デザイン仕様「6. スタイルトークン」)。
private struct NameBuilderActionButton: View {
  let title: String
  let systemImage: String
  let tint: Color
  let foreground: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.system(size: 26, weight: .bold))
        Text(title)
          .font(.system(size: 23, weight: .heavy, design: .rounded))
          .minimumScaleFactor(0.6)
          .lineLimit(1)
      }
      .foregroundStyle(foreground)
      .frame(maxWidth: .infinity, minHeight: 84)
      .background(tint, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
          .strokeBorder(DesignColor.ink, lineWidth: 5)
      }
    }
    .buttonStyle(.plain)
  }
}

/// 正解したときに全面へ出すゲット演出。
private struct NameBuilderGetOverlay: View {
  let result: QuizResult
  let imageCache: PokemonImageCache?
  let onNext: () -> Void

  var body: some View {
    ZStack {
      DesignColor.yellow.opacity(0.97).ignoresSafeArea()

      VStack(spacing: 16) {
        Spacer(minLength: 0)
        QuizSpriteImage(pokemon: result.pokemon, imageCache: imageCache, size: 172)
          .frame(width: 214, height: 214)
          .background(DesignColor.paper, in: Circle())
          .overlay(Circle().strokeBorder(DesignColor.ink, lineWidth: 6))

        Text(result.isNewCatch ? NameBuilderText.getHeadline : NameBuilderText.correctHeadline)
          .font(.system(size: 62, weight: .heavy, design: .rounded))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .shadow(color: DesignColor.ink, radius: 0, x: 3, y: 0)
          .shadow(color: DesignColor.ink, radius: 0, x: -3, y: 0)
          .shadow(color: DesignColor.ink, radius: 0, x: 0, y: 3)
          .shadow(color: DesignColor.ink, radius: 0, x: 0, y: -3)

        Text(result.pokemon.japaneseName)
          .font(.system(size: 42, weight: .heavy, design: .rounded))
          .foregroundStyle(DesignColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.4)
          .padding(.horizontal, 24)
          .padding(.vertical, 12)
          .background(DesignColor.cream, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .strokeBorder(DesignColor.ink, lineWidth: 5)
          }

        Text(result.isNewCatch ? NameBuilderText.registered : NameBuilderText.alreadyRegistered)
          .font(.system(size: 18, weight: .heavy, design: .rounded))
          .foregroundStyle(DesignColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
        Spacer(minLength: 0)

        Button(action: onNext) {
          Text(NameBuilderText.next)
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(DesignColor.green, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(DesignColor.ink, lineWidth: 5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("name_builder_next_button")
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 28)
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("name_builder_get_overlay")
  }
}

/// 子ビューを横に並べ、入り切らない分を次の行へ折り返して中央に寄せる。
///
/// マスとタイルは幅が固定で、列数に合わせて伸ばしたくないため `LazyVGrid` ではなくこの `Layout` を使う。
private struct WrappingRows: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let rows = rows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
    return CGSize(
      width: proposal.width ?? rows.map(\.width).max() ?? 0,
      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
    )
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) {
    var y = bounds.minY
    for row in rows(maxWidth: bounds.width, subviews: subviews) {
      var x = bounds.minX + (bounds.width - row.width) / 2
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(
          at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
          proposal: ProposedViewSize(size)
        )
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  /// 折り返した 1 行ぶんの並び。
  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var row = Row()

    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      if !row.indices.isEmpty, row.width + spacing + size.width > maxWidth {
        rows.append(row)
        row = Row()
      }

      row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      row.height = max(row.height, size.height)
      row.indices.append(index)
    }

    if !row.indices.isEmpty {
      rows.append(row)
    }
    return rows
  }
}

/// 間違えた時にマスを横へ揺らす効果。`shakeCount` を 1 増やすと 1 往復ぶん揺れる。
private struct ShakeEffect: GeometryEffect {
  var shakeCount: CGFloat

  var animatableData: CGFloat {
    get { shakeCount }
    set { shakeCount = newValue }
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    // 幅 10pt で 2 往復させると、揺れが見えて画面からははみ出さない。
    ProjectionTransform(CGAffineTransform(translationX: 10 * sin(shakeCount * .pi * 4), y: 0))
  }
}

#Preview {
  NavigationStack {
    NameBuilderView()
  }
  .modelContainer(PersistenceController(isStoredInMemoryOnly: true).container)
}
