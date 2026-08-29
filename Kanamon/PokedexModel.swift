import Foundation
import Observation
import SwiftData

/// ずかん画面がポケモン一覧を読み込む過程の状態を表す。
enum PokedexLoadingState: Equatable {
  case loading
  case loaded
  case failed
}

/// 図鑑番号を `No.001` 形式の 3 桁で表記する。ずかんのセルと各画面のヘッダーで使う。
func pokedexNumberText(id: Int) -> String {
  String(format: "No.%03d", id)
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

  /// 進捗バーの塗り幅に使う 0〜1 の割合。一覧が空なら 0。
  var progressFraction: Double {
    pokemons.isEmpty ? 0 : Double(caughtCount) / Double(pokemons.count)
  }

  /// ヘッダーに出す図鑑番号の範囲。一覧が空の間は末尾を `---` にする。
  var numberRangeText: String {
    guard let first = pokemons.first, let last = pokemons.last else {
      return "No.--- - ---"
    }

    return "\(pokedexNumberText(id: first.id)) - \(String(format: "%03d", last.id))"
  }

  func isCaught(_ pokemon: Pokemon) -> Bool {
    caughtPokemonIDs.contains(pokemon.id)
  }

  /// ポケモン一覧とゲット状況を読み込む。同じ保存内容に対して何度呼んでも同じ結果になる。
  func load() async {
    state = .loading

    do {
      caughtPokemonIDs = try learningProgressStore.caughtPokemonIDs()
      pokemons = try await repository.loadFirstGeneration()
      state = .loaded
    } catch {
      state = .failed
    }
  }

  /// ゲット状況だけを読み直す。ポケモン一覧の再取得は行わない。
  func reloadCaughtPokemonIDs() {
    caughtPokemonIDs = (try? learningProgressStore.caughtPokemonIDs()) ?? caughtPokemonIDs
  }
}
