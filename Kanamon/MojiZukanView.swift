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

/// もじ ずかん画面で使う色。デザイン仕様 (documents/design/README.md「6. スタイルトークン」) に合わせる。
enum MojiZukanStyle {
  /// インク (文字・枠) `#33241A`
  static let ink = Color(red: 0.200, green: 0.141, blue: 0.102)
  /// クリーム (シートの地) `#FFF6E3`
  static let cream = Color(red: 1.000, green: 0.965, blue: 0.890)
  /// もじずかんの地の色 `#FFF0F6`
  static let background = Color(red: 1.000, green: 0.941, blue: 0.965)
  /// 砂 (未習の文字・未ゲット) `#F0E3C9`
  static let sand = Color(red: 0.941, green: 0.890, blue: 0.788)
  /// 砂の枠 `#C8B698`
  static let sandBorder = Color(red: 0.784, green: 0.714, blue: 0.596)
  /// 砂の文字 `#A8977A`
  static let sandInk = Color(red: 0.659, green: 0.592, blue: 0.478)
  /// 青 (ひらがなの併記) `#1F7FC4`
  static let blue = Color(red: 0.122, green: 0.498, blue: 0.769)
  /// 黄 (進捗のピル・該当文字の下線) `#FFC22E`
  static let yellow = Color(red: 1.000, green: 0.761, blue: 0.180)
  /// 緑 (進捗バー) `#4CC66A`
  static let green = Color(red: 0.298, green: 0.776, blue: 0.416)
  /// 図鑑の赤 (該当文字) `#D93B2B`
  static let red = Color(red: 0.851, green: 0.231, blue: 0.169)
}

/// もじ ずかん画面。五十音 46 文字を 5 列で並べ、出会った文字だけを色付きで埋める。
///
/// 文字をタップするとその音を読み上げ、その文字が名前に入っているポケモンを下から出すシートで見せる。
/// 進捗はこの画面では増えない (よみれんしゅう・クイズ・かきれんしゅう・なまえ づくりが追記する)。
struct MojiZukanView: View {
  /// よみれんしゅうへ送るための、ホーム画面が持つ NavigationStack の経路。
  ///
  /// この画面の中で `navigationDestination` を宣言するとシートが出なくなるため、遷移先の登録は
  /// ホーム画面側にまとめ、この画面は経路への追加だけを行う。
  @Binding var path: NavigationPath

  @Environment(\.modelContext) private var modelContext

  @State private var readCharacters: Set<Character> = []
  @State private var caughtPokemonIDs: Set<Int> = []
  @State private var pokemon: [Pokemon] = []
  @State private var loadState: MojiZukanLoadState = .loading
  @State private var selection: MojiZukanSelection?

  private var readCount: Int {
    GojuonTable.readCount(in: readCharacters)
  }

  var body: some View {
    VStack(spacing: 14) {
      progressCard
      gojuonCard
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MojiZukanStyle.background)
    .navigationTitle(MojiZukanText.title)
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .sheet(item: $selection) { selection in
      CharacterPokemonSheet(
        character: selection.character,
        pokemon: PokemonCharacterSearch.pokemon(containing: selection.character, in: pokemon),
        caughtPokemonIDs: caughtPokemonIDs,
        loadState: loadState,
        onSelect: { pokemon in
          self.selection = nil
          path.append(MojiZukanYomiRenshuTarget(pokemonID: pokemon.id))
        }
      )
    }
  }

  private var progressCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        Text(MojiZukanText.description)
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("\(readCount) / \(GojuonTable.characters.count)")
          .font(.system(size: 16, weight: .heavy, design: .rounded))
          .padding(.horizontal, 11)
          .frame(height: 40)
          .background(MojiZukanStyle.yellow, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
              .stroke(MojiZukanStyle.ink, lineWidth: 4)
          )
      }
      MojiZukanProgressBar(ratio: Double(readCount) / Double(GojuonTable.characters.count))
    }
    .foregroundStyle(MojiZukanStyle.ink)
    .padding(14)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(MojiZukanStyle.ink, lineWidth: 5)
    )
  }

  private var gojuonCard: some View {
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
              KanaSpeechSynthesizer.shared.speak(String(character))
            } label: {
              GojuonCell(character: character, isRead: readCharacters.contains(character))
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
        .stroke(MojiZukanStyle.ink, lineWidth: 5)
    )
  }

  private func load() async {
    let store = LearningProgressStore(modelContext: modelContext)
    readCharacters = (try? store.readCharacters()) ?? []
    caughtPokemonIDs = (try? store.caughtPokemonIDs()) ?? []

    do {
      pokemon = try await PokemonRepository(modelContext: modelContext).loadFirstGeneration()
      loadState = .loaded
    } catch {
      loadState = .failed
    }
  }
}

/// 逆引きに使うポケモンの読み込み状況。シートに出す文言を切り替えるために持つ。
enum MojiZukanLoadState {
  case loading
  case loaded
  case failed
}

/// 逆引きシートで表示中の文字。
private struct MojiZukanSelection: Identifiable {
  let character: Character

  var id: Character { character }
}

/// 逆引きシートから選んだポケモン。よみれんしゅうへの遷移先を表す。
struct MojiZukanYomiRenshuTarget: Hashable {
  let pokemonID: Int
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
        .foregroundStyle(isRead ? MojiZukanStyle.blue : MojiZukanStyle.sandInk)
    }
    .foregroundStyle(isRead ? MojiZukanStyle.ink : MojiZukanStyle.sandInk)
    .frame(maxWidth: .infinity, minHeight: 62)
    .background(
      isRead ? Color.white : MojiZukanStyle.sand,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(isRead ? MojiZukanStyle.ink : MojiZukanStyle.sandBorder, lineWidth: 3)
    )
  }
}

/// 46 文字のうち何文字を読めたかを示す進捗バー。
private struct MojiZukanProgressBar: View {
  let ratio: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(MojiZukanStyle.cream)
        Capsule()
          .fill(MojiZukanStyle.green)
          .frame(width: proxy.size.width * min(max(ratio, 0), 1))
      }
    }
    .frame(height: 22)
    .overlay(Capsule().stroke(MojiZukanStyle.ink, lineWidth: 4))
  }
}

/// タップした文字が名前に入っているポケモンを並べる、下から出るシート。
private struct CharacterPokemonSheet: View {
  let character: Character
  let pokemon: [Pokemon]
  let caughtPokemonIDs: Set<Int>
  let loadState: MojiZukanLoadState
  let onSelect: (Pokemon) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      ScrollView {
        VStack(spacing: 8) {
          if let note {
            MojiZukanNote(text: note)
          }
          ForEach(pokemon, id: \.id) { pokemon in
            let isCaught = caughtPokemonIDs.contains(pokemon.id)
            Button {
              guard isCaught else { return }
              KanaSpeechSynthesizer.shared.speak(pokemon.japaneseName)
              onSelect(pokemon)
            } label: {
              CharacterPokemonRow(
                pokemon: pokemon,
                character: character,
                isCaught: isCaught
              )
            }
            .buttonStyle(.plain)
          }
          if !pokemon.isEmpty && pokemon.contains(where: { !caughtPokemonIDs.contains($0.id) }) {
            MojiZukanNote(text: MojiZukanText.notCaughtHint)
          }
        }
        .padding(.bottom, 8)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(MojiZukanStyle.cream)
    .presentationDetents([.fraction(0.74), .large])
    .presentationDragIndicator(.visible)
  }

  /// ポケモンが 1 匹も並ばない理由 (読み込み中 / 読み込み失敗 / 該当なし) を出す。
  private var note: String? {
    guard pokemon.isEmpty else {
      return nil
    }

    return switch loadState {
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
          .foregroundStyle(MojiZukanStyle.blue)
      }
      .frame(width: 62, height: 62)
      .background(MojiZukanStyle.yellow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(MojiZukanStyle.ink, lineWidth: 4)
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
          .foregroundStyle(MojiZukanStyle.ink)
          .frame(width: 52, height: 52)
          .background(Color.white, in: Circle())
          .overlay(Circle().stroke(MojiZukanStyle.ink, lineWidth: 4))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(MojiZukanText.close)
    }
    .foregroundStyle(MojiZukanStyle.ink)
  }
}

/// 逆引きシートの 1 行。ゲット済みなら名前を、未ゲットならシルエットと「？？？」を出す。
private struct CharacterPokemonRow: View {
  let pokemon: Pokemon
  let character: Character
  let isCaught: Bool

  var body: some View {
    HStack(spacing: 12) {
      PokemonSpriteView(pokemon: pokemon, isCaught: isCaught)
      VStack(alignment: .leading, spacing: 4) {
        Text(String(format: "No.%03d", pokemon.id))
          .font(.system(size: 12, weight: .heavy, design: .rounded))
          .opacity(0.55)
        if isCaught {
          HStack(spacing: 0) {
            ForEach(PokemonCharacterSearch.nameCharacters(of: pokemon, highlighting: character)) { nameCharacter in
              Text(String(nameCharacter.character))
                .font(.system(size: 23, weight: .heavy, design: .rounded))
                .foregroundStyle(nameCharacter.isMatch ? MojiZukanStyle.red : MojiZukanStyle.ink)
                .overlay(alignment: .bottom) {
                  if nameCharacter.isMatch {
                    MojiZukanStyle.yellow.frame(height: 4)
                  }
                }
            }
          }
        } else {
          Text(MojiZukanText.unknownName)
            .font(.system(size: 23, weight: .heavy, design: .rounded))
            .foregroundStyle(MojiZukanStyle.sandInk)
        }
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(MojiZukanStyle.ink)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(MojiZukanStyle.ink, lineWidth: 4)
    )
  }
}

/// シートに出す説明の 1 行。
private struct MojiZukanNote: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 15, weight: .bold, design: .rounded))
      .foregroundStyle(MojiZukanStyle.ink)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(MojiZukanStyle.sand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

/// キャッシュ済みのスプライト画像を出す。未ゲットのポケモンはシルエットにしてネタバレを避ける。
private struct PokemonSpriteView: View {
  let pokemon: Pokemon
  let isCaught: Bool

  @State private var imageData: Data?

  var body: some View {
    Group {
      if let imageData, let image = UIImage(data: imageData) {
        Image(uiImage: image)
          .renderingMode(isCaught ? .original : .template)
          .resizable()
          .scaledToFit()
          .foregroundStyle(Color.black.opacity(0.34))
      } else {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(MojiZukanStyle.sand)
      }
    }
    .frame(width: 52, height: 52)
    .task {
      imageData = try? await PokemonImageCache.shared?.imageData(for: pokemon)
    }
  }
}

#Preview {
  @Previewable @State var path = NavigationPath()

  NavigationStack(path: $path) {
    MojiZukanView(path: $path)
  }
  .modelContainer(PersistenceController(isStoredInMemoryOnly: true).container)
}
