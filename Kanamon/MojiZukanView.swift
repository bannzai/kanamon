import SwiftData
import SwiftUI

/// もじ ずかん画面に出す固定の文言。
///
/// 子どもが読めるように漢字を使わず、ひらがな・カタカナと分かち書きの空白だけで書く
/// (`MojiZukanTests` で検証する)。
enum MojiZukanText {
  static let title = "もじ ずかん"
  static let description = "なまえ を よんだり かいたり すると もじ が うまって いくよ"
  static let loading = "よみこみちゅう"
  static let loadFailed = "モンスター を よみこめなかったよ  つながって から もう いちど ひらいてね"
  static let noPokemon = "この もじ が つく モンスター は まだ いないよ"
  static let notCaughtHint = "クイズ で あてると なまえ が わかるよ"
  static let unknownName = "？？？"
  static let yomiRenshu = "よみれんしゅう"
  static let close = "とじる"

  static func sheetTitle(for character: Character) -> String {
    "\(character) が つく モンスター"
  }

  static func pokemonCount(_ count: Int) -> String {
    "\(count) ひき"
  }

  /// 画面に出す固定の文言 (文字数で変わらないもの) の一覧。
  static let all: [String] = [
    title, description, loading, loadFailed, noPokemon, notCaughtHint, unknownName, yomiRenshu, close,
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
  @State private var model: MojiZukanModel?
  @State private var selection: MojiZukanSelection?

  var body: some View {
    VStack(spacing: 14) {
      if let model {
        progressCard(model: model)
        gojuonCard(model: model)
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MojiZukanColor.background)
    .navigationTitle(MojiZukanText.title)
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: YomiRenshuDestination.self) { _ in
      // よみれんしゅう (issue #6) ができるまでの仮画面。#6 でポケモン ID を受け取る画面に差し替える
      PlaceholderView(title: MojiZukanText.yomiRenshu)
    }
    .task {
      let model = self.model ?? MojiZukanModel(modelContext: modelContext)
      self.model = model

      if model.state != .loaded {
        await model.load()
      }
    }
    .sheet(item: $selection) { selection in
      if let model {
        CharacterPokemonSheet(
          character: selection.character,
          model: model,
          onSelect: { pokemon in
            self.selection = nil
            path.append(YomiRenshuDestination(pokemonID: pokemon.id))
          }
        )
      }
    }
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
          repeating: GridItem(.flexible(), spacing: 5),
          count: GojuonTable.columnCount
        ),
        spacing: 5
      ) {
        ForEach(Array(GojuonTable.cells.enumerated()), id: \.offset) { _, character in
          if let character {
            Button {
              selection = MojiZukanSelection(character: character)
              SpeechSynthesizer.shared.speak(String(character))
            } label: {
              GojuonCell(character: character, isRead: model.isRead(character))
            }
            .buttonStyle(.plain)
          } else {
            Color.clear.frame(minHeight: 62)
          }
        }
      }
      .padding(12)
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
  let onSelect: (Pokemon) -> Void

  @Environment(\.dismiss) private var dismiss

  private var pokemon: [Pokemon] {
    model.pokemons(containing: character)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      ScrollView {
        VStack(spacing: 8) {
          if let note {
            MojiZukanNote(text: note)
          }
          ForEach(pokemon, id: \.id) { pokemon in
            let isCaught = model.isCaught(pokemon)
            Button {
              guard isCaught else { return }
              SpeechSynthesizer.shared.speak(pokemon.japaneseName)
              onSelect(pokemon)
            } label: {
              CharacterPokemonRow(
                pokemon: pokemon,
                character: character,
                isCaught: isCaught,
                imageCache: model.imageCache
              )
            }
            .buttonStyle(.plain)
          }
          if !pokemon.isEmpty && pokemon.contains(where: { !model.isCaught($0) }) {
            MojiZukanNote(text: MojiZukanText.notCaughtHint)
          }
        }
        .padding(.bottom, 8)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DesignColor.cream)
    .presentationDetents([.fraction(0.74), .large])
    .presentationDragIndicator(.visible)
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
        Text(MojiZukanText.sheetTitle(for: character))
          .font(.system(size: 20, weight: .heavy, design: .rounded))
        Text(MojiZukanText.pokemonCount(pokemon.count))
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .opacity(0.65)
      }
      Spacer(minLength: 0)

      // 下へ引いて閉じる操作は子どもには難しいため、押して閉じるボタンも出す。
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 22, weight: .heavy))
          .foregroundStyle(DesignColor.ink)
          .frame(width: 52, height: 52)
          .background(Color.white, in: Circle())
          .overlay(Circle().stroke(DesignColor.ink, lineWidth: 4))
      }
      .buttonStyle(.plain)
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
            ForEach(PokemonCharacterSearch.nameCharacters(of: pokemon, highlighting: character)) { nameCharacter in
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

  NavigationStack(path: $path) {
    MojiZukanView(path: $path)
  }
  .modelContainer(PersistenceController(isStoredInMemoryOnly: true).container)
}
