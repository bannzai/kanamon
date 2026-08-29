import Foundation
import SwiftData
import SwiftUI

/// よみれんしゅう画面に出す固定の文言。
///
/// 子どもが読めるようにひらがな・カタカナと空白だけで書く (`YomiRenshuTests` で検証する)。
enum YomiRenshuText {
  static let title = "よみれんしゅう"
  static let playAll = "ぜんぶ よむ"
  static let stopPlaying = "とめる"
  static let loading = "よみこみちゅう"
  static let failed = "よみこめなかったよ"
  static let retry = "もういちど"
  static let swipeHint = "よこ に スワイプ で つぎ へ"

  /// 画面に出す固定文言のすべて。かな以外が混ざっていないことの検証に使う。
  static let all: [String] = [title, playAll, stopPlaying, loading, failed, retry, swipeHint]
}

/// よみれんしゅう画面だけで使う色。共通の色は `DesignColor` から参照する。
private enum YomiRenshuPalette {
  static let ink = DesignColor.ink
  /// #EAF6FF (README「6. スタイルトークン」の よみ 画面の地の色)
  static let background = Color(hex: 0xEAF6FF)
  static let highlight = DesignColor.yellow
  static let red = DesignColor.red
  /// #1F7FC4 (プロトタイプの --blue-dk。ひらがなの併記に使う)
  static let hiragana = Color(hex: 0x1F7FC4)
}

/// ポケモンの名前を 1 文字ずつ読み上げて、カタカナの読みを練習する画面。
struct YomiRenshuView: View {
  private let initialPokemonID: Int?

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var model: YomiRenshuModel? = nil

  /// 送りと判定する指の横移動の下限。縦スクロールのつもりの指を送りと誤認しない大きさにする。
  private static let swipeHorizontalDistance: CGFloat = 56
  /// 送りと判定する横移動と縦移動の比。斜めに滑った指を送りと誤認しないため縦より十分大きいことを求める。
  private static let swipeHorizontalToVerticalRatio: CGFloat = 1.6
  /// 内容の最大幅 (documents/design/README.md「7. iPad での拡大方針」の 520pt)。
  /// iPad では横に引き伸ばさず中央に寄せて、子どもが目で追える行長に収める。
  private static let contentMaximumWidth: CGFloat = 520

  /// `modelContext` から model を組み立てる通常の入口。
  ///
  /// - Parameter initialPokemonID: 開始位置のポケモン。ホームからは指定がないため省略時は先頭から始める
  init(initialPokemonID: Int? = nil) {
    self.initialPokemonID = initialPokemonID
  }

  /// Preview で架空のデータを入れた model に差し替えるための入口。`@State` を初期値ごと差し替える。
  init(model: YomiRenshuModel) {
    initialPokemonID = nil
    _model = State(initialValue: model)
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // NavigationStack は自前の地の色 (白) を敷くため、画面ごとの地の色で塗り直す (筐体は ContentView が 1 度だけ包む)
      .background(YomiRenshuPalette.background)
      .toolbar(.hidden, for: .navigationBar)
      .onDisappear {
        model?.stop()
      }
      .task {
        let model =
          self.model
          ?? YomiRenshuModel(modelContext: modelContext, initialPokemonID: initialPokemonID)
        self.model = model
        await model.load()
      }
  }

  @ViewBuilder
  private var content: some View {
    if let model {
      switch model.state {
      case .loading:
        loading
      case .failed:
        failed(model: model)
      case .loaded:
        loaded(model: model)
      }
    } else {
      loading
    }
  }

  private var loading: some View {
    VStack(spacing: 16) {
      header(pokemon: nil)
      Spacer()
      ProgressView()
      Text(YomiRenshuText.loading)
        .font(.system(size: 26, weight: .heavy, design: .rounded))
        .foregroundStyle(YomiRenshuPalette.ink)
      Spacer()
    }
    .padding(20)
  }

  private func failed(model: YomiRenshuModel) -> some View {
    VStack(spacing: 24) {
      header(pokemon: nil)
      Spacer()
      Text(YomiRenshuText.failed)
        .font(.system(size: 26, weight: .heavy, design: .rounded))
        .foregroundStyle(YomiRenshuPalette.ink)
      Button {
        Task { await model.load() }
      } label: {
        Text(YomiRenshuText.retry)
          .font(.system(size: 30, weight: .heavy, design: .rounded))
          .foregroundStyle(.white)
          .padding(.horizontal, 32)
          .frame(minHeight: 96)
          .background(
            InkCard(cornerRadius: 30, fill: YomiRenshuPalette.red, borderWidth: 5, shadowOffset: 9)
          )
      }
      .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
      Spacer()
    }
    .padding(20)
  }

  private func loaded(model: YomiRenshuModel) -> some View {
    GeometryReader { proxy in
      ScrollView(.vertical) {
        VStack(spacing: 16) {
          header(pokemon: model.currentPokemon)
          PokemonSpriteCard(pokemon: model.currentPokemon, imageCache: model.imageCache)
          characterCards(model: model)
          if let tipText = model.tipText {
            tipNote(tipText: tipText)
          }
          Spacer(minLength: 0)
          playButton(model: model)
          footer(model: model)
        }
        .padding(20)
        .frame(maxWidth: Self.contentMaximumWidth)
        .frame(maxWidth: .infinity)
        // 画面に収まる高さの時も Spacer が効いて下のボタンが画面の下端に寄るよう、画面の高さを下限にする
        .frame(minHeight: proxy.size.height)
        .contentShape(Rectangle())
        .simultaneousGesture(swipe(model: model))
      }
    }
  }

  /// 見出しと、右端の 3 桁の図鑑番号ピル。
  private func header(pokemon: Pokemon?) -> some View {
    HStack(spacing: 12) {
      PokedexBackButton { dismiss() }
      Text(YomiRenshuText.title)
        .font(.system(size: 30, weight: .heavy, design: .rounded))
        .foregroundStyle(YomiRenshuPalette.ink)
      Spacer(minLength: 0)
      if let pokemon {
        Text(String(format: "No.%03d", pokemon.id))
          .font(.system(size: 20, weight: .heavy, design: .rounded))
          .foregroundStyle(YomiRenshuPalette.ink)
          .padding(.horizontal, 14)
          .padding(.vertical, 6)
          .background(YomiRenshuPalette.highlight, in: Capsule())
          .overlay(Capsule().strokeBorder(YomiRenshuPalette.ink, lineWidth: 4))
      }
    }
  }

  private func characterCards(model: YomiRenshuModel) -> some View {
    WrappingRows(spacing: 8) {
      ForEach(model.characters) { character in
        YomiRenshuCharacterCell(
          character: character,
          isHighlighted: model.highlightedIndices.contains(character.index)
        ) {
          Task { await model.tap(index: character.index) }
        }
      }
    }
  }

  /// にている もじ をタップした時に出す見分け方のノート。
  private func tipNote(tipText: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text("👀")
        .font(.system(size: 26))
      Text(tipText)
        .font(.system(size: 18, weight: .bold, design: .rounded))
        .foregroundStyle(YomiRenshuPalette.ink)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(14)
    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(YomiRenshuPalette.red, lineWidth: 4)
    )
  }

  private func playButton(model: YomiRenshuModel) -> some View {
    Button {
      if model.isPlaying {
        model.stop()
      } else {
        Task { await model.playAll() }
      }
    } label: {
      Text(model.isPlaying ? YomiRenshuText.stopPlaying : YomiRenshuText.playAll)
        .font(.system(size: 30, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(
          InkCard(cornerRadius: 30, fill: YomiRenshuPalette.red, borderWidth: 5, shadowOffset: 9)
        )
    }
    .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
  }

  /// 前後へ送るボタンと、いま何匹目かの表示。
  private func footer(model: YomiRenshuModel) -> some View {
    HStack(spacing: 12) {
      stepButton(symbol: "◀") { model.previous() }
      VStack(spacing: 4) {
        Text("\(model.currentIndex + 1) / \(model.pokemons.count)")
          .font(.system(size: 22, weight: .heavy, design: .rounded))
          .foregroundStyle(YomiRenshuPalette.ink)
        Text(YomiRenshuText.swipeHint)
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .foregroundStyle(YomiRenshuPalette.ink.opacity(0.7))
          .minimumScaleFactor(0.6)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      stepButton(symbol: "▶") { model.next() }
    }
  }

  private func stepButton(symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(symbol)
        .font(.system(size: 26, weight: .heavy, design: .rounded))
        .foregroundStyle(YomiRenshuPalette.ink)
        .frame(width: 60, height: 60)
        .background(
          InkCard(cornerRadius: 20, fill: .white, borderWidth: 4, shadowOffset: 4)
        )
    }
    .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
  }

  /// 指を横に払った時だけ前後のポケモンへ送る。
  private func swipe(model: YomiRenshuModel) -> some Gesture {
    DragGesture(minimumDistance: 20)
      .onEnded { value in
        guard abs(value.translation.width) >= Self.swipeHorizontalDistance,
          abs(value.translation.width)
            > abs(value.translation.height) * Self.swipeHorizontalToVerticalRatio
        else {
          return
        }

        if value.translation.width < 0 {
          model.next()
        } else {
          model.previous()
        }
      }
  }
}

/// カード・ボタンの下地。太い枠と、ぼかさず真下へずらした影を付ける。
///
/// 影を中身ごと落とすと文字にも影が付いてしまうため、下地だけに影を持たせて `background` へ敷く。
private struct InkCard: View {
  let cornerRadius: CGFloat
  let fill: Color
  /// 枠と影の色。にている もじ のセルだけ赤にする。
  var borderColor: Color = YomiRenshuPalette.ink
  let borderWidth: CGFloat
  /// 影を真下へずらす量 (documents/design/README.md「6. スタイルトークン」の 4〜9px)。
  let shadowOffset: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(fill)
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(borderColor, lineWidth: borderWidth)
      )
      .shadow(color: borderColor, radius: 0, x: 0, y: shadowOffset)
  }
}

/// 名前の 1 文字を、上にカタカナ・下に対応するひらがなの 2 段で見せるセル。
private struct YomiRenshuCharacterCell: View {
  let character: YomiRenshuCharacter
  /// いま読み上げている文字として光らせるか。
  let isHighlighted: Bool
  let action: () -> Void

  /// セルの幅。指で確実に押せるよう 60pt 以上にしつつ、iPhone の横幅 (390 − 左右の余白 40 = 350) に
  /// `WrappingRows` の間隔 8pt を挟んで 5 文字 (60 × 5 + 8 × 4 = 332) が 1 行で並ぶ大きさにする。
  private static let width: CGFloat = 60

  /// にている もじ は枠と影を赤にして、注意して見る文字だと分かるようにする。
  private var borderColor: Color {
    character.isSimilar ? YomiRenshuPalette.red : YomiRenshuPalette.ink
  }

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Text(String(character.katakana))
          .font(.system(size: 33, weight: .heavy, design: .rounded))
          .foregroundStyle(YomiRenshuPalette.ink)
        Text(character.hiragana)
          .font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(YomiRenshuPalette.hiragana)
      }
      .minimumScaleFactor(0.6)
      .lineLimit(1)
      .frame(width: Self.width, height: 74)
      .contentShape(Rectangle())
      .background(
        InkCard(
          cornerRadius: 14,
          fill: isHighlighted ? YomiRenshuPalette.highlight : .white,
          borderColor: borderColor,
          borderWidth: 4,
          shadowOffset: isHighlighted ? 8 : 4
        )
      )
      .offset(y: isHighlighted ? -5 : 0)
      .scaleEffect(isHighlighted ? 1.07 : 1)
    }
    .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
    .animation(.easeOut(duration: 0.12), value: isHighlighted)
  }
}

/// モンスターの画像を白いカードに載せて見せる。
///
/// 画像の読み込みは、取れるまで間隔を空けて取り直す ずかん の `PokemonSpriteView` に任せる。
private struct PokemonSpriteCard: View {
  let pokemon: Pokemon?
  let imageCache: PokemonImageCache?

  var body: some View {
    ZStack {
      if let pokemon {
        // よみれんしゅう は ゲット の有無で見た目を変えないため、常にカラーで見せる
        PokemonSpriteView(pokemon: pokemon, isCaught: true, imageCache: imageCache)
          .padding(10)
      } else {
        ProgressView()
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 190)
    .background(
      InkCard(cornerRadius: 26, fill: .white, borderWidth: 5, shadowOffset: 8)
    )
  }
}

/// 子が横幅に収まらなくなったら次の行へ折り返し、各行を中央に寄せて並べるレイアウト。
///
/// 名前が長いポケモンでも文字カードを縮めずに全部見せるために使う。
private struct WrappingRows: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    // 幅の提案がない時は折り返しようがないため、1 行に並べた大きさを返す
    let rows = rows(maximumWidth: proposal.width ?? .infinity, sizes: sizes)
    let rowHeights = rows.map { rowHeight(indices: $0, sizes: sizes) }

    return CGSize(
      width: rows.map { rowWidth(indices: $0, sizes: sizes) }.max() ?? 0,
      height: rowHeights.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
    )
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    var y = bounds.minY

    for row in rows(maximumWidth: bounds.width, sizes: sizes) {
      let rowHeight = rowHeight(indices: row, sizes: sizes)
      var x = bounds.minX + (bounds.width - rowWidth(indices: row, sizes: sizes)) / 2

      for index in row {
        subviews[index].place(
          at: CGPoint(x: x, y: y + (rowHeight - sizes[index].height) / 2),
          proposal: ProposedViewSize(sizes[index])
        )
        x += sizes[index].width + spacing
      }

      y += rowHeight + spacing
    }
  }

  /// 各行に入る子の位置を、先頭から順に詰めて決める。
  private func rows(maximumWidth: CGFloat, sizes: [CGSize]) -> [[Int]] {
    var rows: [[Int]] = []
    var row: [Int] = []
    var width: CGFloat = 0

    for (index, size) in sizes.enumerated() {
      let additionalWidth = row.isEmpty ? size.width : spacing + size.width
      if !row.isEmpty, width + additionalWidth > maximumWidth {
        rows.append(row)
        row = [index]
        width = size.width
      } else {
        row.append(index)
        width += additionalWidth
      }
    }

    if !row.isEmpty {
      rows.append(row)
    }

    return rows
  }

  private func rowWidth(indices: [Int], sizes: [CGSize]) -> CGFloat {
    // 子が 1 つも無い行は生まれないが、max(0,) で間隔が負にならないようにしておく
    indices.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(max(0, indices.count - 1))
  }

  private func rowHeight(indices: [Int], sizes: [CGSize]) -> CGFloat {
    indices.map { sizes[$0].height }.max() ?? 0
  }
}

/// Preview 用に、架空のポケモンだけを入れたメモリ内のコンテナと model を用意する。
@MainActor
private func makeYomiRenshuPreview() -> (model: YomiRenshuModel, container: ModelContainer) {
  let controller = PersistenceController(isStoredInMemoryOnly: true)
  let modelContext = ModelContext(controller.container)
  let previewPokemons = [
    Pokemon(id: 1, japaneseName: "テストモン", spriteURL: URL(string: "https://example.com/1.png")!),
    Pokemon(id: 2, japaneseName: "ツナミモン♀", spriteURL: URL(string: "https://example.com/2.png")!),
  ]

  for pokemon in previewPokemons {
    modelContext.insert(PokemonCacheEntry(pokemon: pokemon))
  }
  try? modelContext.save()

  return (
    YomiRenshuModel(
      modelContext: modelContext,
      repository: PokemonRepository(modelContext: modelContext, pokemonIDs: previewPokemons.map(\.id))
    ),
    controller.container
  )
}

#Preview {
  let preview = makeYomiRenshuPreview()

  NavigationStack {
    YomiRenshuView(model: preview.model)
  }
  .modelContainer(preview.container)
}
