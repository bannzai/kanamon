import SwiftUI

/// まだ実装していない画面のかわりに表示する画面。
///
/// ホームからの遷移と復帰を先に成立させるために置く。各画面が実装されたら差し替える。
struct PlaceholderView: View {
  let title: String

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 14) {
      HStack(spacing: 12) {
        PokedexBackButton { dismiss() }

        Text(title)
          .font(.system(size: 30, weight: .black, design: .rounded))
          .foregroundStyle(DesignColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: 64)

      Spacer()

      Text("じゅんびちゅう")
        .font(.system(size: 30, weight: .black, design: .rounded))
        .foregroundStyle(DesignColor.sandDark)

      Spacer()
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .toolbar(.hidden, for: .navigationBar)
  }
}

#Preview {
  PokedexDeviceFrame {
    NavigationStack {
      PlaceholderView(title: "かきれんしゅう")
    }
  }
}
