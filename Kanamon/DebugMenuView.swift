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

    /// 動作確認で「読めた」にする文字。
    /// もじ ずかんの五十音表が部分的に埋まった見た目を作れるよう、複数の行にまたがるものを選んでいる
    private static let sampleReadCharacters: [Character] = [
      "ア", "イ", "ウ", "カ", "キ", "ク", "サ", "シ", "タ", "ナ", "モ", "ン",
    ]

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

        Section("もじのしんちょく") {
          Button("サンプルをよめたことにする") {
            markSampleRead()
          }
          .accessibilityIdentifier("debug_mark_sample_read")

          Button("もじのしんちょくをけす") {
            removeAllCharacterProgress()
          }
          .accessibilityIdentifier("debug_remove_all_character_progress")
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

    /// よみれんしゅう (#6)・かきれんしゅう (#21)・なまえ づくり (#22) が未実装の間、
    /// もじ ずかんの埋まり具合を確認するために「読めた文字」を投入する。
    private func markSampleRead() {
      let store = LearningProgressStore(modelContext: modelContext)
      do {
        for character in Self.sampleReadCharacters {
          try store.markRead(character: character)
        }
      } catch {
        assertionFailure("読めた文字の保存に失敗しました: \(error)")
      }
    }

    /// 保存済みの文字単位の進捗 (読めた・書けた) をすべて消す。取り消しの仕様がないため
    /// LearningProgressStore には置かず、開発者メニューだけが直接消す。
    private func removeAllCharacterProgress() {
      do {
        try modelContext.delete(model: CharacterProgressEntry.self)
        try modelContext.save()
      } catch {
        assertionFailure("文字の進捗の削除に失敗しました: \(error)")
      }
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
