import Foundation
import SwiftData

/// PokeAPI から取得し、画面機能へ渡すポケモンのメタデータを表す。
struct Pokemon: Equatable, Sendable {
  let id: Int
  let japaneseName: String
  let spriteURL: URL
}

/// アプリで使用する SwiftData コンテナを構築して保持する。
@MainActor
struct PersistenceController {
  static let shared = PersistenceController()

  let container: ModelContainer

  init(isStoredInMemoryOnly: Bool = false) {
    do {
      if !isStoredInMemoryOnly,
        let applicationSupportDirectory = FileManager.default.urls(
          for: .applicationSupportDirectory,
          in: .userDomainMask
        ).first
      {
        try FileManager.default.createDirectory(
          at: applicationSupportDirectory,
          withIntermediateDirectories: true
        )
      }

      let configuration = ModelConfiguration(isStoredInMemoryOnly: isStoredInMemoryOnly)
      container = try ModelContainer(
        for: PokemonCacheEntry.self,
        configurations: configuration
      )
    } catch {
      fatalError("SwiftData コンテナの作成に失敗しました: \(error)")
    }
  }
}

/// PokeAPI からポケモンのメタデータを取得するデータソースを表す。
protocol PokemonDataSource: Sendable {
  func fetchPokemon(id: Int) async throws -> Pokemon
}

/// 端末内の SwiftData に保存するポケモンのメタデータキャッシュを表す。
@Model
final class PokemonCacheEntry {
  @Attribute(.unique) private(set) var pokemonID: Int
  private(set) var japaneseName: String
  private(set) var spriteURLString: String
  private(set) var updatedDateTime: Date

  init(pokemon: Pokemon, updatedDateTime: Date = .now) {
    pokemonID = pokemon.id
    japaneseName = pokemon.japaneseName
    spriteURLString = pokemon.spriteURL.absoluteString
    self.updatedDateTime = updatedDateTime
  }

  var pokemon: Pokemon? {
    guard let spriteURL = URL(string: spriteURLString) else {
      return nil
    }

    return Pokemon(id: pokemonID, japaneseName: japaneseName, spriteURL: spriteURL)
  }
}

/// SwiftData のキャッシュを優先し、未取得分だけを PokeAPI から補完する。
@MainActor
final class PokemonRepository {
  private let modelContext: ModelContext
  private let dataSource: any PokemonDataSource
  private let pokemonIDs: [Int]

  init(
    modelContext: ModelContext,
    dataSource: any PokemonDataSource = PokeAPIClient(),
    pokemonIDs: [Int] = Array(1...151)
  ) {
    self.modelContext = modelContext
    self.dataSource = dataSource
    self.pokemonIDs = pokemonIDs
  }

  func loadFirstGeneration() async throws -> [Pokemon] {
    let descriptor = FetchDescriptor<PokemonCacheEntry>(
      sortBy: [SortDescriptor(\PokemonCacheEntry.pokemonID)]
    )
    let requestedIDs = Set(pokemonIDs)
    let cachedEntries = try modelContext.fetch(descriptor)
    var pokemonByID: [Int: Pokemon] = [:]

    for entry in cachedEntries where requestedIDs.contains(entry.pokemonID) {
      if let pokemon = entry.pokemon {
        pokemonByID[pokemon.id] = pokemon
      }
    }

    let missingIDs = pokemonIDs.filter { pokemonByID[$0] == nil }
    var fetchedPokemon: [Pokemon] = []
    fetchedPokemon.reserveCapacity(missingIDs.count)

    for id in missingIDs {
      let pokemon = try await dataSource.fetchPokemon(id: id)
      guard pokemon.id == id else {
        throw PokemonRepositoryError.unexpectedPokemonID(expected: id, actual: pokemon.id)
      }
      fetchedPokemon.append(pokemon)
    }

    for pokemon in fetchedPokemon {
      modelContext.insert(PokemonCacheEntry(pokemon: pokemon))
      pokemonByID[pokemon.id] = pokemon
    }

    if !fetchedPokemon.isEmpty {
      try modelContext.save()
    }

    return pokemonIDs.compactMap { pokemonByID[$0] }
  }
}

/// PokeAPI の応答と要求した ID が一致しない場合のエラーを表す。
enum PokemonRepositoryError: Error, Equatable {
  case unexpectedPokemonID(expected: Int, actual: Int)
}
