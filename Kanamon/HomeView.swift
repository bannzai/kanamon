import SwiftData
import SwiftUI

/// ホーム画面に並べる導線 1 つ分の表示内容。`AppDestination` から文言・記号・色を組み立てる。
///
/// 表示用の値を enum ではなく画面側で持つための型 (`.claude/rules/coding-rules-entity.md`)。
struct HomeMenuItem: Identifiable {
  let destination: AppDestination
  /// ボタンに表示する名前。子どもが読めるようにひらがな・カタカナだけで書く。
  let title: String
  let systemImage: String
  /// アイコンの色。白地の角丸枠の中に置くため、確定デザインの原色から選ぶ。
  let iconTint: Color
  /// ボタンの背景色。確定デザイン (documents/design/README.md「2. 画面一覧と遷移」) の割り当てに従う。
  let tint: Color
  /// タイトルと説明文の色。明るい黄・ピンクの上ではインク、濃い色の上では白にする。
  let labelColor: Color

  var id: AppDestination { destination }

  init(destination: AppDestination) {
    self.destination = destination
    switch destination {
    case .zukan:
      title = "ずかん"
      systemImage = "book.fill"
      iconTint = DesignColor.green
      tint = DesignColor.yellow
      labelColor = DesignColor.ink
    case .yomiRenshu:
      title = "よみれんしゅう"
      systemImage = "speaker.wave.3.fill"
      iconTint = DesignColor.yellow
      tint = DesignColor.blue
      labelColor = DesignColor.paper
    case .kakiRenshu:
      title = "かきれんしゅう"
      systemImage = "pencil"
      iconTint = DesignColor.blue
      tint = DesignColor.green
      labelColor = DesignColor.paper
    case .quiz:
      title = "クイズ"
      systemImage = "questionmark"
      iconTint = DesignColor.ink
      tint = DesignColor.red
      labelColor = DesignColor.paper
    case .namaeZukuri:
      title = "なまえ づくり"
      systemImage = "square.grid.2x2.fill"
      iconTint = DesignColor.yellow
      tint = DesignColor.purple
      labelColor = DesignColor.paper
    case .mojiZukan:
      title = "もじ ずかん"
      systemImage = "character.book.closed.fill"
      iconTint = DesignColor.pink
      tint = DesignColor.pink
      labelColor = DesignColor.ink
    }
  }

  static let all: [HomeMenuItem] = AppDestination.allCases.map(HomeMenuItem.init(destination:))
}

/// ホーム画面に出す固定の文言。子どもが読めるようにひらがな・カタカナだけで書く。
enum HomeText {
  static let title = "カナモン"
  static let subtitle = "なまえ を よんで かいて\nあつめよう"

  /// 導線ボタンの説明文。ずかんともじ ずかんは進捗の数が入る
  static func description(destination: AppDestination, progress: HomeProgress) -> String {
    switch destination {
    case .zukan:
      "あつめた モンスター \(progress.caughtPokemonCount) ひき"
    case .yomiRenshu:
      "1 もじずつ ひかって よみあげる"
    case .kakiRenshu:
      "かきじゅん を みて なぞる"
    case .quiz:
      "あてたら ゲット できる"
    case .namaeZukuri:
      "もじ を ならべて なまえ に する"
    case .mojiZukan:
      "よめた もじ \(progress.readCharacterCount) / \(KatakanaGojuon.characters.count)"
    }
  }
}

/// ホーム画面に出す進捗の数え上げを表す。保存済みの進捗から作る。
struct HomeProgress: Equatable {
  let caughtPokemonCount: Int
  /// 五十音 46 文字のうち読めた文字の数。長音符など表に無い文字は数えない
  let readCharacterCount: Int

  static let empty = HomeProgress(caughtPokemonCount: 0, readCharacterCount: 0)

  /// ゲット数のピルに出す「N / M」。M はアプリが扱うポケモンの総数
  var caughtCountText: String {
    "\(caughtPokemonCount) / \(PokemonCatalog.firstGenerationIDs.count)"
  }
}

/// ホーム画面。確定デザインの 6 つの導線を、赤い図鑑にはめ込まれた画面の中に並べる。
///
/// 子どもが 1 人で迷わないよう、階層はホームと各画面の 2 段だけにする。
struct HomeView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var progress = HomeProgress.empty
  /// 遷移の深さが変わるたびに進捗を読み直すために持つ。0 に戻った時がホームへの復帰
  @State private var navigationPath = NavigationPath()

  var body: some View {
    NavigationStack(path: $navigationPath) {
      // 6 つ並べるとはめ込み画面に入りきらない小型端末 (iPhone SE 等) では
      // clipShape で下が欠けてしまうため、収まらない時だけスクロールさせる。
      // 収まる端末では minHeight が画面の高さを埋め、ボタンが残りの高さを等分する
      GeometryReader { proxy in
        ScrollView {
          VStack(spacing: 11) {
            hero

            VStack(spacing: 10) {
              ForEach(HomeMenuItem.all) { item in
                NavigationLink(value: item.destination) {
                  HomeMenuButtonLabel(
                    item: item,
                    description: HomeText.description(destination: item.destination, progress: progress)
                  )
                }
                .buttonStyle(
                  PokedexCardButtonStyle(
                    background: item.tint,
                    cornerRadius: 30,
                    borderWidth: 5,
                    shadowHeight: 9
                  )
                )
              }
            }
            .frame(maxHeight: .infinity)
          }
          .padding(20)
          .frame(maxWidth: .infinity, minHeight: proxy.size.height)
        }
        .scrollBounceBehavior(.basedOnSize)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // NavigationStack は自前の地の色 (白) を敷くため、画面ごとにクリームを塗り直す
      .background(DesignColor.cream)
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(for: AppDestination.self) { destination in
        switch destination {
        case .zukan:
          PokedexView()
        case .yomiRenshu:
          YomiRenshuView()
        case .quiz:
          QuizView()
        case .kakiRenshu:
          KakiRenshuView()
        case .namaeZukuri, .mojiZukan:
          PlaceholderView(title: HomeMenuItem(destination: destination).title)
        }
      }
      // クイズ等でゲットしてから戻った時にも数え直すため、遷移の深さが変わるたびに読み直す。
      // SwiftData の @Query は ModelContainer 無しでの body 評価 (テスト・Preview) で落ちるため使わない
      .task(id: navigationPath.count) {
        progress = Self.loadProgress(modelContext: modelContext)
      }
    }
  }

  /// 保存済みの進捗を読み出す。読み出しに失敗してもホームは表示したいので 0 件として扱う。
  @MainActor
  private static func loadProgress(modelContext: ModelContext) -> HomeProgress {
    let store = LearningProgressStore(modelContext: modelContext)
    do {
      return HomeProgress(
        caughtPokemonCount: try store.caughtPokemonIDs().count,
        readCharacterCount: try store.readCharacters().filter(KatakanaGojuon.characterSet.contains).count
      )
    } catch {
      assertionFailure("進捗の読み出しに失敗しました: \(error)")
      return .empty
    }
  }

  private var hero: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(HomeText.title)
          .font(.system(size: 40, weight: .black, design: .rounded))
          .foregroundStyle(DesignColor.red)
        Text(HomeText.subtitle)
          .font(.system(size: 15, weight: .heavy, design: .rounded))
          .foregroundStyle(DesignColor.ink)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Text(progress.caughtCountText)
        .font(.system(size: 16, weight: .black, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(DesignColor.ink)
        .padding(.horizontal, 11)
        .frame(height: 40)
        .background(DesignColor.yellow)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(DesignColor.ink, lineWidth: 4)
        )
        .background(
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(DesignColor.ink)
            .offset(y: 4)
        )
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 14)
    .background(DesignColor.paper)
    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .strokeBorder(DesignColor.ink, lineWidth: 5)
    )
    .background(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .fill(DesignColor.ink)
        .offset(y: 8)
    )
  }
}

/// ホーム画面の導線ボタンの見た目。子どもの指でも押しやすいように高さと文字を大きくする。
private struct HomeMenuButtonLabel: View {
  let item: HomeMenuItem
  let description: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: item.systemImage)
        .font(.system(size: 30, weight: .black))
        .foregroundStyle(item.iconTint)
        .frame(width: 62, height: 62)
        .background(DesignColor.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(DesignColor.ink, lineWidth: 4)
        )

      VStack(alignment: .leading, spacing: 5) {
        Text(item.title)
          .font(.system(size: 27, weight: .black, design: .rounded))
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(description)
          .font(.system(size: 13, weight: .heavy, design: .rounded))
          .opacity(0.8)
          .lineLimit(2)
      }
      .foregroundStyle(item.labelColor)

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    // 62pt のアイコンがカードの上下の枠に接しないようにする。この余白のぶん、
    // ボタンが縮む時も高さは 74pt (62 + 6 + 6) より下がらない
    .padding(.vertical, 6)
    // 高さは画面いっぱいまで伸ばして 6 つで等分する。プロトタイプの 86 を下限にすると
    // 筐体と safe area に削られた画面 (iPhone 16 Pro で約 695pt) に収まらずはみ出すため、
    // 下限は確定デザインのタップ領域の最小値 (README「6. スタイルトークン > 形」) の 60 にする
    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: .infinity)
  }
}

#Preview {
  PokedexDeviceFrame {
    HomeView()
  }
  .modelContainer(PersistenceController(isStoredInMemoryOnly: true).container)
}
