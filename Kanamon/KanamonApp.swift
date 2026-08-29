import SwiftUI
import SwiftData

@main
struct KanamonApp: App {
  private let persistenceController = PersistenceController.shared

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .modelContainer(persistenceController.container)
  }
}
