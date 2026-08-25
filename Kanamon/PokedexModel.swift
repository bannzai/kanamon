import Foundation
import Observation
import SwiftData

/// ずかん画面がポケモン一覧を読み込む過程の状態を表す。
enum PokedexLoadingState: Equatable {
  case loading
  case loaded
  case failed
}

/// ずかん画面が表示するポケモン一覧とゲット状況を組み立てる。
@MainActor
@Observable
final class PokedexModel {
  private(set) var pokemons: [Pokemon] = []
  private(set) var caughtPokemonIDs: Set<Int> = []
  private(set) var state: PokedexLoadingState = .loading

  let imageCache: PokemonImageCache?

  private let repository: PokemonRepository
  private let caughtPokemonStore: CaughtPokemonStore

  convenience init(modelContext: ModelContext) {
    self.init(
      repository: PokemonRepository(modelContext: modelContext),
      caughtPokemonStore: CaughtPokemonStore(modelContext: modelContext),
      imageCache: try? PokemonImageCache()
    )
  }

  init(
    repository: PokemonRepository,
    caughtPokemonStore: CaughtPokemonStore,
    imageCache: PokemonImageCache?
  ) {
    self.repository = repository
    self.caughtPokemonStore = caughtPokemonStore
    self.imageCache = imageCache
  }

  /// 一覧に並ぶポケモンのうち、ゲット済みの数を返す。
  var caughtCount: Int {
    pokemons.reduce(into: 0) { count, pokemon in
      if caughtPokemonIDs.contains(pokemon.id) {
        count += 1
      }
    }
  }

  /// ゲット済みの数と一覧の総数を「12 / 151」の形で返す。
  var progressText: String {
    "\(caughtCount) / \(pokemons.count)"
  }

  func isCaught(_ pokemon: Pokemon) -> Bool {
    caughtPokemonIDs.contains(pokemon.id)
  }

  /// ポケモン一覧とゲット状況を読み込む。同じ保存内容に対して何度呼んでも同じ結果になる。
  func load() async {
    state = .loading

    do {
      caughtPokemonIDs = try caughtPokemonStore.caughtPokemonIDs()
      pokemons = try await repository.loadFirstGeneration()
      state = .loaded
    } catch {
      state = .failed
    }
  }

  /// ゲット状況だけを読み直す。ポケモン一覧の再取得は行わない。
  func reloadCaughtPokemonIDs() {
    caughtPokemonIDs = (try? caughtPokemonStore.caughtPokemonIDs()) ?? caughtPokemonIDs
  }

  #if DEBUG
    /// 開発者メニューからゲット状況を書き換えるためにストアを渡す。
    var debugCaughtPokemonStore: CaughtPokemonStore {
      caughtPokemonStore
    }
  #endif
}
