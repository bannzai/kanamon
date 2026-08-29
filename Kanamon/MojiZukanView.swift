import SwiftData
import SwiftUI

/// もじ ずかん画面に出す固定の文言。
///
/// 子どもが読めるように漢字を使わず、ひらがな・カタカナと分かち書きの空白だけで書く
/// (`MojiZukanTests` で検証する)。
enum MojiZukanText {
  static let title = "もじ ずかん"
  static let description = "なまえ を よんだり あてたり すると もじ が うまって いくよ"
  static let loading = "よみこみちゅう"
  static let loadFailed = "モンスター を よみこめなかったよ  つながって から もう いちど ひらいてね"
  static let noPokemon = "この もじ が つく モンスター は まだ いないよ"
  static let notCaughtHint = "クイズ で あてると なまえ が わかるよ"
  static let unknownName = "？？？"
  static let close = "とじる"
  static let read = "よめた"
  static let notRead = "まだ"

  /// 名前のどこが探している文字に当たるかを、目で見なくても分かるように読み上げる文言。
  static func matchPositions(character: Character, positions: [Int]) -> String {
    guard !positions.isEmpty else {
      return ""
    }

    return "\(character) は \(positions.map { "\($0) ばんめ" }.joined(separator: " と "))"
  }

  static func sheetTitle(character: Character) -> String {
    "\(character) が つく モンスター"
  }

  static func pokemonCount(count: Int) -> String {
    "\(count) ひき"
  }

  /// 画面に出す固定の文言 (文字数で変わらないもの) の一覧。
  static let all: [String] = [
    title, description, loading, loadFailed, noPokemon, notCaughtHint, unknownName, close, read,
    notRead,
  ]
}

/// もじ ずかん画面だけで使う色。共通のトークンは `DesignColor` を使い、ここには画面固有のものだけ置く。
enum MojiZukanColor {
  /// もじずかんの地の色 `#FFF0F6` (documents/design/README.md「6. スタイルトークン > 画面ごとの地の色」)
  static let background = Color(hex: 0xFFF0F6)
  /// ひらがなの併記に使う濃い青 `#1F7FC4`。
  /// `DesignColor.blue` (#2BA9FF) は小さい文字だと白地で読みづらいため、プロトタイプの --blue-dk を使う。
  static let blueDark = Color(hex: 0x1F7FC4)
}

/// もじ ずかん画面。五十音 46 文字を 5 列で並べ、出会った文字だけを色付きで埋める。
///
/// 文字をタップするとその音を読み上げ、その文字が名前に入っているポケモンを下から出すシートで見せる。
/// 進捗はこの画面では増えない (よみれんしゅう・クイズ・かきれんしゅう・なまえ づくりが追記する)。
struct MojiZukanView: View {
  /// ホーム画面が持つ NavigationStack の経路。逆引きシートからよみれんしゅうへ送るために受け取る。
  ///
  /// ずかん画面のようにセルへ `NavigationLink` を置く形にできないため (シートの中は経路の外にある)、
  /// 経路へ値を積んで遷移させる。
  @Binding var path: NavigationPath

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var model: MojiZukanModel?
  @State private var selection: MojiZukanSelection?

  var body: some View {
    ZStack {
      VStack(spacing: 14) {
        header
          .padding(.horizontal, 20)

        if let model {
          progressCard(model: model)
            .padding(.horizontal, 20)
          gojuonCard(model: model)
            .padding(.horizontal, GojuonLayout.cardHorizontalPadding)
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      // シートを出している間は、背面をスワイプ操作で辿れないようにする。
      // 半透明のビューは見た目を覆うだけで、VoiceOver からは背面が読めてしまうため
      .accessibilityHidden(selection != nil)

      // 逆引きは OS のシートではなく画面の中に重ねる。OS のシートはウインドウが出すため、
      // ContentView が敷いた図鑑の筐体の上にかぶさって「図鑑にはめ込まれた画面」の構図が崩れる
      if let selection, let model {
        CharacterPokemonSheet(
          character: selection.character,
          model: model,
          onClose: { close() },
          onSelect: { pokemon in
            close()
            path.append(YomiRenshuDestination(pokemonID: pokemon.id))
          }
        )
      }
    }
    .padding(.vertical, 20)
    // iPad では横に引き伸ばさず中央寄せにする (documents/design/README.md「7. iPad での拡大方針」)。
    // 引き伸ばすと 5 列の各セルが極端に横長になり、文字を追いにくくなる。
    .frame(maxWidth: PokedexLayout.maximumScreenWidth)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // NavigationStack は自前の地の色 (白) を敷くため、画面ごとに地の色を塗り直す。
    // クイズ画面と同じく、確定デザインの画面ごとの地の色を使う
    .background(MojiZukanColor.background)
    .toolbar(.hidden, for: .navigationBar)
    .navigationDestination(for: YomiRenshuDestination.self) { destination in
      YomiRenshuView(initialPokemonID: destination.pokemonID)
    }
    // よみれんしゅう等から戻った時にも表と進捗を追随させるため、遷移の深さが変わるたびに読み直す
    .task(id: path.count) {
      let model = self.model ?? MojiZukanModel(modelContext: modelContext)
      self.model = model

      if model.state == .loaded {
        model.reloadProgress()
      } else {
        await model.load()
      }
    }
  }

  private func open(character: Character) {
    withAnimation(.easeOut(duration: 0.22)) {
      selection = MojiZukanSelection(character: character)
    }
  }

  private func close() {
    withAnimation(.easeOut(duration: 0.22)) {
      selection = nil
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      PokedexBackButton { dismiss() }

      Text(MojiZukanText.title)
        .font(.system(size: 30, weight: .black, design: .rounded))
        .foregroundStyle(DesignColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 64)
  }

  private func progressCard(model: MojiZukanModel) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        Text(MojiZukanText.description)
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(model.progressText)
          .font(.system(size: 16, weight: .heavy, design: .rounded))
          .monospacedDigit()
          .padding(.horizontal, 11)
          .frame(height: 40)
          .background(DesignColor.yellow, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
              .stroke(DesignColor.ink, lineWidth: 4)
          )
      }
      MojiZukanProgressBar(ratio: model.progressFraction)
    }
    .foregroundStyle(DesignColor.ink)
    .padding(14)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(DesignColor.ink, lineWidth: 5)
    )
  }

  private func gojuonCard(model: MojiZukanModel) -> some View {
    ScrollView {
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: GojuonLayout.cellSpacing),
          count: GojuonTable.columnCount
        ),
        spacing: GojuonLayout.cellSpacing
      ) {
        ForEach(Array(GojuonTable.cells.enumerated()), id: \.offset) { _, character in
          if let character {
            Button {
              open(character: character)
              SpeechSynthesizer.shared.speak(String(character))
            } label: {
              GojuonCell(character: character, isRead: model.isRead(character))
            }
            .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
          } else {
            Color.clear.frame(minHeight: 62)
          }
        }
      }
      .padding(GojuonLayout.cardInnerPadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(DesignColor.ink, lineWidth: 5)
    )
  }
}

/// 逆引きシートで表示中の文字。
private struct MojiZukanSelection: Identifiable {
  let character: Character

  var id: Character { character }
}

/// 五十音表の 1 マス。カタカナを大きく、対応するひらがなを小さく併記する。
private struct GojuonCell: View {
  let character: Character
  let isRead: Bool

  var body: some View {
    VStack(spacing: 2) {
      Text(String(character))
        .font(.system(size: 22, weight: .heavy, design: .rounded))
      Text(KatakanaConverter.hiragana(from: String(character)))
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(isRead ? MojiZukanColor.blueDark : DesignColor.sandDark)
    }
    .foregroundStyle(isRead ? DesignColor.ink : DesignColor.sandDark)
    .frame(maxWidth: .infinity, minHeight: 62)
    .background(
      isRead ? Color.white : DesignColor.sand,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(isRead ? DesignColor.ink : DesignColor.sandBorder, lineWidth: 3)
    )
    // 読めたかどうかを色だけで表すと VoiceOver では区別できないため、値としても伝える
    .accessibilityElement(children: .combine)
    .accessibilityValue(isRead ? MojiZukanText.read : MojiZukanText.notRead)
  }
}

/// 46 文字のうち何文字を読めたかを示す進捗バー。
private struct MojiZukanProgressBar: View {
  let ratio: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(DesignColor.cream)
        Capsule()
          .fill(DesignColor.green)
          .frame(width: proxy.size.width * min(max(ratio, 0), 1))
      }
    }
    .frame(height: 22)
    .overlay(Capsule().stroke(DesignColor.ink, lineWidth: 4))
  }
}

/// タップした文字が名前に入っているポケモンを並べる、下から出るシート。
private struct CharacterPokemonSheet: View {
  let character: Character
  let model: MojiZukanModel
  let onClose: () -> Void
  let onSelect: (Pokemon) -> Void

  /// カードが画面を覆う高さの上限 (documents/design/README.md のプロトタイプの 74%)。
  private static let maximumHeightRatio = 0.74

  private var pokemon: [Pokemon] {
    model.pokemons(containing: character)
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      DesignColor.ink.opacity(0.42)
        .onTapGesture { onClose() }

      GeometryReader { proxy in
        card
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(maxHeight: proxy.size.height * Self.maximumHeightRatio, alignment: .bottom)
          .frame(maxHeight: .infinity, alignment: .bottom)
      }
    }
    .transition(.opacity)
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      ScrollView {
        VStack(spacing: 8) {
          if let note {
            MojiZukanNote(text: note)
          }
          ForEach(pokemon, id: \.id) { pokemon in
            let row = CharacterPokemonRow(
              pokemon: pokemon,
              character: character,
              isCaught: model.isCaught(pokemon),
              imageCache: model.imageCache
            )
            // 未ゲットの行は押しても何も起きないため、ボタンにしない。
            // ボタンのままだと VoiceOver が操作できる行として読み上げてしまう。
            if model.isCaught(pokemon) {
              Button {
                SpeechSynthesizer.shared.speak(pokemon.japaneseName)
                onSelect(pokemon)
              } label: {
                row
              }
              .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
            } else {
              row
            }
          }
          if !pokemon.isEmpty && pokemon.contains(where: { !model.isCaught($0) }) {
            MojiZukanNote(text: MojiZukanText.notCaughtHint)
          }
        }
        .padding(.bottom, 8)
      }
    }
    .padding(16)
    .background(DesignColor.cream)
    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
    .overlay(
      UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
        .strokeBorder(DesignColor.ink, lineWidth: 5)
    )
  }

  /// ポケモンが 1 匹も並ばない理由 (読み込み中 / 読み込み失敗 / 該当なし) を出す。
  private var note: String? {
    guard pokemon.isEmpty else {
      return nil
    }

    return switch model.state {
    case .loading: MojiZukanText.loading
    case .failed: MojiZukanText.loadFailed
    case .loaded: MojiZukanText.noPokemon
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(spacing: 0) {
        Text(String(character))
          .font(.system(size: 28, weight: .heavy, design: .rounded))
        Text(KatakanaConverter.hiragana(from: String(character)))
          .font(.system(size: 12, weight: .bold, design: .rounded))
          .foregroundStyle(MojiZukanColor.blueDark)
      }
      .frame(width: 62, height: 62)
      .background(DesignColor.yellow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(DesignColor.ink, lineWidth: 4)
      )

      VStack(alignment: .leading, spacing: 4) {
        Text(MojiZukanText.sheetTitle(character: character))
          .font(.system(size: 20, weight: .heavy, design: .rounded))
        Text(MojiZukanText.pokemonCount(count: pokemon.count))
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .opacity(0.65)
      }
      Spacer(minLength: 0)

      // 下へ引いて閉じる操作は子どもには難しいため、押して閉じるボタンも出す。
      Button {
        onClose()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 22, weight: .heavy))
          .foregroundStyle(DesignColor.ink)
          .frame(width: 52, height: 52)
          .background(Color.white, in: Circle())
          .overlay(Circle().stroke(DesignColor.ink, lineWidth: 4))
          // 見た目の円は 52pt のまま、押せる範囲だけを子ども向けの最小タップ領域 60pt へ広げる
          // (documents/design/README.md「6. スタイルトークン > 形」)。
          .frame(width: 60, height: 60)
          .contentShape(Rectangle())
      }
      .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
      .accessibilityLabel(MojiZukanText.close)
    }
    .foregroundStyle(DesignColor.ink)
  }
}

/// 逆引きシートの 1 行。ゲット済みなら名前を、未ゲットならシルエットと「？？？」を出す。
private struct CharacterPokemonRow: View {
  let pokemon: Pokemon
  let character: Character
  let isCaught: Bool
  let imageCache: PokemonImageCache?

  private var nameCharacters: [NameCharacter] {
    PokemonCharacterSearch.nameCharacters(pokemon: pokemon, highlighting: character)
  }

  /// 一致した文字が名前の何番目かを 1 から数えて返す。
  private var matchPositions: [Int] {
    nameCharacters.filter(\.isMatch).map { $0.id + 1 }
  }

  var body: some View {
    HStack(spacing: 12) {
      PokemonSpriteView(pokemon: pokemon, isCaught: isCaught, imageCache: imageCache)
        .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 4) {
        Text(String(format: "No.%03d", pokemon.id))
          .font(.system(size: 12, weight: .heavy, design: .rounded))
          .opacity(0.55)
        if isCaught {
          HStack(spacing: 0) {
            ForEach(nameCharacters) { nameCharacter in
              Text(String(nameCharacter.character))
                .font(.system(size: 23, weight: .heavy, design: .rounded))
                .foregroundStyle(nameCharacter.isMatch ? DesignColor.red : DesignColor.ink)
                .overlay(alignment: .bottom) {
                  if nameCharacter.isMatch {
                    DesignColor.yellow.frame(height: 4)
                  }
                }
            }
          }
        } else {
          Text(MojiZukanText.unknownName)
            .font(.system(size: 23, weight: .heavy, design: .rounded))
            .foregroundStyle(DesignColor.sandDark)
        }
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(DesignColor.ink)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(DesignColor.ink, lineWidth: 4)
    )
    // 名前のどこが該当文字かを赤字と下線だけで表すと VoiceOver では分からないため、値としても伝える。
    // 正規化して一致する組み合わせ (ヒ に対する ピ など) は名前を聞くだけでは対応が付かない
    .accessibilityElement(children: .combine)
    .accessibilityValue(
      isCaught ? MojiZukanText.matchPositions(character: character, positions: matchPositions) : ""
    )
  }
}

/// シートに出す説明の 1 行。
private struct MojiZukanNote: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 15, weight: .bold, design: .rounded))
      .foregroundStyle(DesignColor.ink)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(DesignColor.sand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

#Preview {
  @Previewable @State var path = NavigationPath()

  PokedexDeviceFrame {
    NavigationStack(path: $path) {
      MojiZukanView(path: $path)
    }
  }
  .modelContainer(PersistenceController(isStoredInMemoryOnly: true).container)
}
