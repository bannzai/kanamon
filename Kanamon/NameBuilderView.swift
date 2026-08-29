import SwiftData
import SwiftUI

/// なまえ づくり画面。絵を見て文字タイルを 1 つずつ選び、名前を組み立てる。
///
/// デザインは `documents/design/README.md`「4-2. なまえ づくり」に従う。
struct NameBuilderView: View {
  @Environment(\.modelContext) private var modelContext

  @State private var pokemonList: [Pokemon] = []
  @State private var pokemonIndex = 0
  @State private var game: NameBuilderGame?
  @State private var loadErrorText: String?
  /// 正解した時に先頭から順に緑へ光らせたマスの数。
  @State private var litSlotCount = 0
  /// ゲット演出を出しているか。
  @State private var isCelebrating = false
  /// 間違えた時に横へ揺らすための回数。増やすたびに 1 往復ぶん揺れる。
  @State private var shakeCount = 0

  private var pokemon: Pokemon? {
    pokemonList.indices.contains(pokemonIndex) ? pokemonList[pokemonIndex] : nil
  }

  var body: some View {
    ZStack {
      NameBuilderPalette.background.ignoresSafeArea()

      if let loadErrorText {
        NameBuilderMessage(text: "つうしん が うまく いかなかったよ\n\(loadErrorText)")
      } else if let pokemon, let game {
        content(pokemon: pokemon, game: game)
      } else {
        ProgressView()
          .controlSize(.large)
      }

      if isCelebrating {
        NameBuilderCelebration {
          isCelebrating = false
          advanceToNextPokemon()
        }
      }
    }
    .navigationTitle("なまえづくり")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadPokemonList()
    }
  }

  private func content(pokemon: Pokemon, game: NameBuilderGame) -> some View {
    VStack(spacing: 12) {
      PokemonSpriteCard(pokemon: pokemon)

      Text("もじ を えらんで なまえ に しよう")
        .font(.system(size: 19, weight: .heavy, design: .rounded))
        .foregroundStyle(NameBuilderPalette.ink)

      NameBuilderCard {
        WrappingRows(spacing: 7) {
          ForEach(0..<game.answer.count, id: \.self) { index in
            NameBuilderSlot(
              character: index < game.placed.count ? game.placed[index] : nil,
              isLit: index < litSlotCount
            )
            .onTapGesture {
              tapSlot(index: index)
            }
          }
        }
        .modifier(ShakeEffect(shakeCount: CGFloat(shakeCount)))
      }

      NameBuilderCard {
        WrappingRows(spacing: 8) {
          ForEach(game.tileStates) { tile in
            NameBuilderTile(tile: tile)
              .onTapGesture {
                tapTile(tile: tile)
              }
          }
        }
      }

      HStack(spacing: 10) {
        NameBuilderActionButton(
          title: "1つ もどす",
          systemImage: "arrow.uturn.backward",
          tint: NameBuilderPalette.yellow,
          foreground: NameBuilderPalette.ink
        ) {
          undoLastCharacter()
        }

        NameBuilderActionButton(
          title: "よんで もらう",
          systemImage: "speaker.wave.3.fill",
          tint: NameBuilderPalette.blue,
          foreground: .white
        ) {
          KanaSpeaker.speak(text: pokemon.japaneseName)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: 520)
  }

  private func loadPokemonList() async {
    guard pokemonList.isEmpty else {
      return
    }

    do {
      pokemonList = try await PokemonRepository(modelContext: modelContext).loadFirstGeneration()
      startGame()
    } catch {
      loadErrorText = error.localizedDescription
    }
  }

  /// いま選んでいるポケモンの出題を組み立て直す。同じポケモンなら何度呼んでもやり直しになる。
  private func startGame() {
    guard let pokemon else {
      return
    }

    litSlotCount = 0
    game = NameBuilderGame(
      answer: Array(pokemon.japaneseName),
      tiles: NameBuilderTileMaker.tiles(answer: Array(pokemon.japaneseName))
    )
  }

  private func advanceToNextPokemon() {
    guard !pokemonList.isEmpty else {
      return
    }

    pokemonIndex = (pokemonIndex + 1) % pokemonList.count
    startGame()
  }

  private func tapTile(tile: NameBuilderGame.Tile) {
    guard var game, !tile.isSpent, !isCelebrating else {
      return
    }

    KanaSpeaker.speak(text: String(tile.character))
    game.place(tile: tile)
    self.game = game
    judge()
  }

  private func tapSlot(index: Int) {
    guard var game, !isCelebrating else {
      return
    }

    game.removePlaced(index: index)
    self.game = game
  }

  private func undoLastCharacter() {
    guard var game, !isCelebrating else {
      return
    }

    game.undo()
    self.game = game
  }

  private func judge() {
    guard let game, let judgement = game.judgement() else {
      return
    }

    switch judgement {
    case .correct:
      Task {
        await celebrateCorrectAnswer()
      }
    case .rollback(let keepCount):
      KanaSpeaker.speak(text: "もう いちど")
      withAnimation(.easeInOut(duration: 0.38)) {
        shakeCount += 1
      }
      Task {
        // 揺れが終わってから戻すと、どこまで合っていたかを子どもが見て分かる。
        try? await Task.sleep(for: .milliseconds(420))
        self.game?.rollback(keepCount: keepCount)
      }
    }
  }

  private func celebrateCorrectAnswer() async {
    guard let pokemon, let game else {
      return
    }

    saveProgress(pokemon: pokemon, answer: game.answer)

    for slotIndex in game.answer.indices {
      withAnimation(.easeOut(duration: 0.2)) {
        litSlotCount = slotIndex + 1
      }
      // 先頭から 1 マスずつ光らせて読む順序を示すため、プロトタイプと同じ 90ms 間隔にする。
      try? await Task.sleep(for: .milliseconds(90))
    }

    KanaSpeaker.speak(text: pokemon.japaneseName)
    try? await Task.sleep(for: .milliseconds(480))
    isCelebrating = true
  }

  private func saveProgress(pokemon: Pokemon, answer: [Character]) {
    let store = LearningProgressStore(modelContext: modelContext)
    do {
      try store.markPokemonCaught(id: pokemon.id)
      for character in answer {
        try store.markRead(character: character)
      }
    } catch {
      // 進捗の保存に失敗しても遊び自体は続けられるため、画面は止めずに記録だけ諦める。
    }
  }
}

/// なまえ づくり画面で使う色。デザイン仕様「6. スタイルトークン」の値をそのまま持つ。
enum NameBuilderPalette {
  static let ink = Color(red: 0.20, green: 0.14, blue: 0.10)
  static let background = Color(red: 0.95, green: 0.93, blue: 1.00)
  static let paper = Color.white
  static let slot = Color(red: 0.96, green: 0.95, blue: 1.00)
  static let slotBorder = Color(red: 0.72, green: 0.65, blue: 0.88)
  static let blue = Color(red: 0.17, green: 0.66, blue: 1.00)
  static let blueDark = Color(red: 0.12, green: 0.50, blue: 0.77)
  static let yellow = Color(red: 1.00, green: 0.76, blue: 0.18)
  static let green = Color(red: 0.30, green: 0.78, blue: 0.42)
}

/// 画面の中身を白いカードに載せる枠。太い枠とずらした影で図鑑らしい見た目にする。
private struct NameBuilderCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .padding(.horizontal, 10)
      .background(NameBuilderPalette.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .strokeBorder(NameBuilderPalette.ink, lineWidth: 5)
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
        .font(.system(size: 29, weight: .black, design: .rounded))
        .foregroundStyle(isLit ? .white : NameBuilderPalette.ink)
      Text(character.map { KatakanaConverter.hiragana(from: String($0)) } ?? " ")
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundStyle(isLit ? .white : NameBuilderPalette.blueDark)
    }
    .frame(width: 56, height: 62)
    .background(slotBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    .overlay {
      if character == nil {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .strokeBorder(
            NameBuilderPalette.slotBorder,
            style: StrokeStyle(lineWidth: 4, dash: [7, 6])
          )
      } else {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .strokeBorder(NameBuilderPalette.ink, lineWidth: 4)
      }
    }
  }

  private var slotBackground: Color {
    if isLit {
      NameBuilderPalette.green
    } else if character == nil {
      NameBuilderPalette.slot
    } else {
      NameBuilderPalette.paper
    }
  }
}

/// 下に並べる文字タイル。使い切ったタイルは薄くして押せないことを示す。
private struct NameBuilderTile: View {
  let tile: NameBuilderGame.Tile

  var body: some View {
    VStack(spacing: 2) {
      Text(String(tile.character))
        .font(.system(size: 30, weight: .black, design: .rounded))
        .foregroundStyle(NameBuilderPalette.ink)
      Text(KatakanaConverter.hiragana(from: String(tile.character)))
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundStyle(NameBuilderPalette.blueDark)
    }
    .frame(width: 60, height: 64)
    .background(NameBuilderPalette.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(NameBuilderPalette.ink, lineWidth: 4)
    }
    .opacity(tile.isSpent ? 0.26 : 1)
    .allowsHitTesting(!tile.isSpent)
  }
}

/// 画面の下に置く大きなボタン。子どもの指でも押せるように高さを 84pt にする。
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
          .font(.system(size: 23, weight: .black, design: .rounded))
          .minimumScaleFactor(0.6)
          .lineLimit(1)
      }
      .foregroundStyle(foreground)
      .frame(maxWidth: .infinity, minHeight: 84)
      .background(tint, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
          .strokeBorder(NameBuilderPalette.ink, lineWidth: 5)
      }
    }
    .buttonStyle(.plain)
  }
}

/// ポケモンの画像を載せるカード。画像は `PokemonImageCache` から読み込む。
private struct PokemonSpriteCard: View {
  let pokemon: Pokemon

  @State private var spriteData: Data?

  var body: some View {
    Group {
      if let spriteData, let image = UIImage(data: spriteData) {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(width: 178, height: 178)
      } else {
        ProgressView()
      }
    }
    .frame(maxWidth: .infinity, minHeight: 196)
    .background(NameBuilderPalette.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .strokeBorder(NameBuilderPalette.ink, lineWidth: 5)
    }
    .task(id: pokemon.id) {
      spriteData = nil
      spriteData = try? await PokemonImageCache().imageData(for: pokemon)
    }
  }
}

/// 正解した時に出すゲット演出。放射状の光の上にバッジを重ねる。
private struct NameBuilderCelebration: View {
  let onNext: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.42).ignoresSafeArea()

      VStack(spacing: 24) {
        Text("ゲット")
          .font(.system(size: 62, weight: .black, design: .rounded))
          .foregroundStyle(.white)
          .shadow(color: NameBuilderPalette.ink, radius: 0, x: 0, y: 5)
        Text("ずかん に とうろく したよ")
          .font(.system(size: 20, weight: .heavy, design: .rounded))
          .foregroundStyle(.white)

        Button(action: onNext) {
          Text("つぎへ")
            .font(.system(size: 28, weight: .black, design: .rounded))
            .foregroundStyle(NameBuilderPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(NameBuilderPalette.yellow, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(NameBuilderPalette.ink, lineWidth: 5)
            }
        }
        .buttonStyle(.plain)
      }
      .padding(32)
    }
  }
}

/// 読み込みに失敗した時などに出す案内。
private struct NameBuilderMessage: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 22, weight: .heavy, design: .rounded))
      .foregroundStyle(NameBuilderPalette.ink)
      .multilineTextAlignment(.center)
      .padding(24)
  }
}

/// 子ビューを横に並べ、入り切らない分を次の行へ折り返して中央に寄せる。
///
/// マスとタイルは幅が固定でグリッドの列数に合わせて伸ばしたくないため、`LazyVGrid` ではなくこの `Layout` を使う。
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
      let widthWithSubview = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      if !row.indices.isEmpty, widthWithSubview > maxWidth {
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
