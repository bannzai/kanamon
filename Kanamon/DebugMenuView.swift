#if DEBUG
  import SwiftData
  import SwiftUI

  /// DEBUG ビルドだけに現れる開発者メニュー。
  /// クイズ画面ができるまで、ずかんのゲット済み / 未ゲットの見た目をここから作って動作確認する。
  struct DebugMenuView: View {
    let model: PokedexModel

    @Environment(\.modelContext) private var modelContext

    /// 動作確認で「ゲット済み」にするポケモンの ID。
    /// 1 匹だけではカラー表示とシルエットの並びを見比べにくいため、先頭付近から 3 匹を選んでいる
    private static let sampleCaughtPokemonIDs = [1, 4, 7]

    var body: some View {
      List {
        Section("ゲットじょうきょう") {
          Button("サンプルをゲットずみにする") {
            markSampleCaught()
          }
          .accessibilityIdentifier("debug_mark_sample_caught")

          Button("ゲットじょうきょうをけす") {
            removeAllCaught()
          }
          .accessibilityIdentifier("debug_remove_all_caught")
        }
      }
      .navigationTitle("かいはつしゃメニュー")
    }

    private func markSampleCaught() {
      let store = LearningProgressStore(modelContext: modelContext)
      do {
        for pokemonID in Self.sampleCaughtPokemonIDs {
          try store.markPokemonCaught(id: pokemonID)
        }
      } catch {
        assertionFailure("ゲット状況の保存に失敗しました: \(error)")
      }

      model.reloadCaughtPokemonIDs()
    }

    /// 保存済みのゲット状況をすべて消す。取り消しの仕様がないため LearningProgressStore には置かず、開発者メニューだけが直接消す。
    private func removeAllCaught() {
      do {
        try modelContext.delete(model: CaughtPokemonEntry.self)
        try modelContext.save()
      } catch {
        assertionFailure("ゲット状況の削除に失敗しました: \(error)")
      }

      model.reloadCaughtPokemonIDs()
    }
  }
#endif
