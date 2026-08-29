import SwiftUI

/// ホーム画面に並べる導線 1 つ分の表示内容。`AppDestination` から文言・記号・色を組み立てる。
///
/// 表示用の値を enum ではなく画面側で持つための型 (`.claude/rules/coding-rules-entity.md`)。
struct HomeMenuItem: Identifiable {
  let destination: AppDestination
  /// ボタンに表示する名前。子どもが読めるようにひらがな・カタカナだけで書く。
  let title: String
  let systemImage: String
  /// ボタンの背景色。白文字とのコントラスト比を 4.5:1 以上にする (`HomeViewTests` で検証する)。
  let tint: Color

  var id: AppDestination { destination }

  init(destination: AppDestination) {
    self.destination = destination
    switch destination {
    case .zukan:
      title = "ずかん"
      systemImage = "book.fill"
      tint = Color(red: 0.08, green: 0.46, blue: 0.30)
    case .yomiRenshu:
      title = "よみれんしゅう"
      systemImage = "speaker.wave.3.fill"
      tint = Color(red: 0.72, green: 0.35, blue: 0.02)
    case .quiz:
      title = "クイズ"
      systemImage = "star.fill"
      tint = Color(red: 0.33, green: 0.38, blue: 0.86)
    }
  }

  static let all: [HomeMenuItem] = AppDestination.allCases.map(HomeMenuItem.init(destination:))
}

/// ホーム画面。ずかん・よみれんしゅう・クイズへの導線を大きなボタンで並べる。
///
/// 子どもが 1 人で迷わないよう、階層はホームと各画面の 2 段だけにする。
struct HomeView: View {
  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        ForEach(HomeMenuItem.all) { item in
          NavigationLink(value: item.destination) {
            HomeMenuButtonLabel(item: item)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .background(Color(.systemGroupedBackground))
      .navigationTitle("カナモン")
      .navigationDestination(for: AppDestination.self) { destination in
        switch destination {
        case .zukan:
          PokedexView()
        case .quiz:
          QuizView()
        case .yomiRenshu:
          PlaceholderView(title: HomeMenuItem(destination: destination).title)
        }
      }
    }
  }
}

/// ホーム画面の大きなボタンの見た目。子どもの指でも押しやすいように高さと文字を大きくする。
private struct HomeMenuButtonLabel: View {
  let item: HomeMenuItem

  var body: some View {
    HStack(spacing: 20) {
      Image(systemName: item.systemImage)
        .font(.system(size: 44, weight: .bold))
      Text(item.title)
        .font(.system(size: 40, weight: .heavy, design: .rounded))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 28)
    .frame(maxWidth: .infinity, minHeight: 120)
    .background(item.tint, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
  }
}

#Preview {
  HomeView()
}
