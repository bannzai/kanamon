#if DEBUG

import SwiftData
import SwiftUI

/// DEBUG ビルドだけに出す開発者オプション。動作確認で到達しづらい進捗をタップ操作だけで作る。
///
/// よみれんしゅう (#6)・クイズ (#7)・かきれんしゅう (#21)・なまえ づくり (#22) が未実装の間、
/// もじ ずかんの埋まり具合とゲット済みの表示を simulator で確認するために使う。
/// 起動引数ではなく画面にしているのは、リモート simulator でも同じ手順で操作できるようにするため
/// (`~/.claude/rules/debug-menu-first-for-hard-to-reach-states.md`)。
struct DeveloperOptionsView: View {
  @Environment(\.modelContext) private var modelContext

  @State private var result: String?

  /// 読めたことにする文字。五十音表が部分的に埋まった状態になるよう、複数の行にまたがるものを選ぶ。
  private static let readCharacters: [Character] = [
    "ア", "イ", "ウ", "カ", "キ", "ク", "サ", "シ", "タ", "ナ", "モ", "ン",
  ]

  /// ゲット済みにする図鑑番号。逆引きシートにゲット済みと未ゲットが混ざるよう、先頭の一部だけにする。
  private static let caughtPokemonIDs: [Int] = Array(1...12)

  var body: some View {
    List {
      Section("データ操作") {
        Button("テストデータ作成") {
          seedProgress()
        }
        .accessibilityIdentifier("debug_create_test_data")
      }

      if let result {
        Section("結果") {
          Text(result)
        }
      }
    }
    .navigationTitle("開発者オプション")
    .navigationBarTitleDisplayMode(.inline)
  }

  /// 同じ操作を何度実行しても結果が変わらないように、追記済みの進捗はそのままにする。
  private func seedProgress() {
    let store = LearningProgressStore(modelContext: modelContext)
    do {
      for character in Self.readCharacters {
        try store.markRead(character: character)
      }
      for pokemonID in Self.caughtPokemonIDs {
        try store.markPokemonCaught(id: pokemonID)
      }
      result = "読めた文字 \(Self.readCharacters.count) / ゲット済み \(Self.caughtPokemonIDs.count) を投入しました"
    } catch {
      result = "投入に失敗しました: \(error)"
    }
  }
}

#Preview {
  NavigationStack {
    DeveloperOptionsView()
  }
  .modelContainer(PersistenceController(isStoredInMemoryOnly: true).container)
}

#endif
