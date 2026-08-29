import Foundation
import Observation
import SwiftData

/// もじ ずかん画面が表示する五十音表の進捗と、逆引きに使うポケモン一覧を組み立てる。
///
/// 逆引きシートは読み込みの完了より先に開けるため、シートへ値を渡し切りにせずこのモデルを渡し、
/// 読み込みが終わった時点でシートの中身も更新されるようにする。
@MainActor
@Observable
final class MojiZukanModel {
  private(set) var pokemons: [Pokemon] = []
  private(set) var caughtPokemonIDs: Set<Int> = []
  private(set) var readCharacters: Set<Character> = []
  private(set) var state: PokedexLoadingState = .loading

  let imageCache: PokemonImageCache?

  private let repository: PokemonRepository
  private let learningProgressStore: LearningProgressStore

  convenience init(modelContext: ModelContext) {
    self.init(
      repository: PokemonRepository(modelContext: modelContext),
      learningProgressStore: LearningProgressStore(modelContext: modelContext),
      imageCache: try? PokemonImageCache()
    )
  }

  init(
    repository: PokemonRepository,
    learningProgressStore: LearningProgressStore,
    imageCache: PokemonImageCache?
  ) {
    self.repository = repository
    self.learningProgressStore = learningProgressStore
    self.imageCache = imageCache
  }

  /// 五十音表に並ぶ 46 文字のうち、読めた文字の数。
  var readCount: Int {
    GojuonTable.readCount(in: readCharacters)
  }

  /// 読めた文字の数と 46 文字を「12 / 46」の形で返す。
  var progressText: String {
    "\(readCount) / \(GojuonTable.characters.count)"
  }

  /// 進捗バーの塗り幅に使う 0〜1 の割合。
  var progressFraction: Double {
    Double(readCount) / Double(GojuonTable.characters.count)
  }

  func isRead(_ character: Character) -> Bool {
    readCharacters.contains(character)
  }

  func isCaught(_ pokemon: Pokemon) -> Bool {
    caughtPokemonIDs.contains(pokemon.id)
  }

  /// その文字が名前に入っているポケモンを、図鑑番号の順で返す。
  func pokemons(containing character: Character) -> [Pokemon] {
    PokemonCharacterSearch.pokemon(containing: character, in: pokemons)
  }

  /// 文字の進捗・ゲット状況・ポケモン一覧を読み込む。同じ保存内容に対して何度呼んでも同じ結果になる。
  func load() async {
    state = .loading

    do {
      readCharacters = try learningProgressStore.readCharacters()
      caughtPokemonIDs = try learningProgressStore.caughtPokemonIDs()
      pokemons = try await repository.loadFirstGeneration()
      state = .loaded
    } catch {
      state = .failed
    }
  }
}
