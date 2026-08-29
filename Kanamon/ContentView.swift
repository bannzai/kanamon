import SwiftUI

/// アプリの根っこ。赤い図鑑デバイスの筐体で `HomeView` の `NavigationStack` ごと包み、
/// どの画面でも同じ筐体がはめ込まれて見えるようにする (documents/design/README.md「1. デザインの土台」)。
struct ContentView: View {
  var body: some View {
    PokedexDeviceFrame {
      HomeView()
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(PersistenceController(isStoredInMemoryOnly: true).container)
}
