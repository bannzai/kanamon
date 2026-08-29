import SwiftUI

/// まだ実装していない画面のかわりに表示する画面。
///
/// ホームからの遷移と復帰を先に成立させるために置く。各画面が実装されたら差し替える。
struct PlaceholderView: View {
  let title: String

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 32) {
      Spacer()
      Text(title)
        .font(.system(size: 44, weight: .heavy, design: .rounded))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
      Text("じゅんびちゅう")
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .foregroundStyle(.secondary)
      Spacer()
      Button {
        dismiss()
      } label: {
        Text("もどる")
          .font(.system(size: 36, weight: .heavy, design: .rounded))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, minHeight: 100)
          .background(
            Color(red: 0.45, green: 0.45, blue: 0.50),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
          )
      }
      .buttonStyle(.plain)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    PlaceholderView(title: "ずかん")
  }
}
