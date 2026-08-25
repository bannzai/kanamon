#if DEBUG
  import SwiftUI

  /// DEBUG ビルドだけに現れる開発者メニュー。
  /// クイズ画面ができるまで、ずかんのゲット済み / 未ゲットの見た目をここから作って動作確認する。
  struct DebugMenuView: View {
    let model: PokedexModel

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
      do {
        for pokemonID in Self.sampleCaughtPokemonIDs {
          try model.debugCaughtPokemonStore.markCaught(pokemonID: pokemonID)
        }
      } catch {
        assertionFailure("ゲット状況の保存に失敗しました: \(error)")
      }

      model.reloadCaughtPokemonIDs()
    }

    private func removeAllCaught() {
      do {
        try model.debugCaughtPokemonStore.removeAllCaught()
      } catch {
        assertionFailure("ゲット状況の削除に失敗しました: \(error)")
      }

      model.reloadCaughtPokemonIDs()
    }
  }
#endif
