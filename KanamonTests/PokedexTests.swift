import Foundation
import SwiftData
import XCTest

@testable import Kanamon

final class PokedexTests: XCTestCase {
  @MainActor
  func testStoreSavesCaughtPokemonAndReturnsThemAsIDs() throws {
    let container = try makeContainer()
    let store = CaughtPokemonStore(modelContext: container.mainContext)

    try store.markCaught(pokemonID: 1)
    try store.markCaught(pokemonID: 3)

    XCTAssertEqual(try store.caughtPokemonIDs(), [1, 3])
  }

  @MainActor
  func testStoreKeepsSingleEntryWhenSamePokemonIsMarkedTwice() throws {
    let container = try makeContainer()
    let store = CaughtPokemonStore(modelContext: container.mainContext)

    try store.markCaught(pokemonID: 1)
    try store.markCaught(pokemonID: 1)

    XCTAssertEqual(try store.caughtPokemonIDs(), [1])
    XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CaughtPokemon>()).count, 1)
  }

  @MainActor
  func testModelLoadsPokemonListWithCaughtStatus() async throws {
    let container = try makeContainer()
    let store = CaughtPokemonStore(modelContext: container.mainContext)
    try store.markCaught(pokemonID: 2)
    let model = makeModel(container: container, store: store, pokemonIDs: [1, 2, 3])

    await model.load()

    XCTAssertEqual(model.state, .loaded)
    XCTAssertEqual(model.pokemons.map(\.id), [1, 2, 3])
    XCTAssertFalse(model.isCaught(model.pokemons[0]))
    XCTAssertTrue(model.isCaught(model.pokemons[1]))
  }

  @MainActor
  func testModelProgressTextCountsOnlyPokemonShownInTheList() async throws {
    let container = try makeContainer()
    let store = CaughtPokemonStore(modelContext: container.mainContext)
    try store.markCaught(pokemonID: 1)
    try store.markCaught(pokemonID: 99)
    let model = makeModel(container: container, store: store, pokemonIDs: [1, 2, 3])

    await model.load()

    XCTAssertEqual(model.caughtCount, 1)
    XCTAssertEqual(model.progressText, "1 / 3")
  }

  @MainActor
  func testModelReloadsCaughtStatusWithoutFetchingPokemonAgain() async throws {
    let container = try makeContainer()
    let store = CaughtPokemonStore(modelContext: container.mainContext)
    let dataSource = PokemonDataSourceStub(failingIDs: [])
    let model = makeModel(
      container: container,
      store: store,
      pokemonIDs: [1, 2, 3],
      dataSource: dataSource
    )
    await model.load()
    let requestCountAfterLoad = await dataSource.requestCount()

    try store.markCaught(pokemonID: 3)
    model.reloadCaughtPokemonIDs()
    let requestCountAfterReload = await dataSource.requestCount()

    XCTAssertEqual(model.caughtPokemonIDs, [3])
    XCTAssertEqual(requestCountAfterReload, requestCountAfterLoad)
  }

  @MainActor
  func testModelReportsFailureWhenMetadataCannotBeLoaded() async throws {
    let container = try makeContainer()
    let model = makeModel(
      container: container,
      store: CaughtPokemonStore(modelContext: container.mainContext),
      pokemonIDs: [1, 2],
      dataSource: PokemonDataSourceStub(failingIDs: [2])
    )

    await model.load()

    XCTAssertEqual(model.state, .failed)
  }

  func testDisplayedTextsUseKanaOnly() {
    let texts = [
      PokedexText.title,
      PokedexText.loading,
      PokedexText.failed,
      PokedexText.retry,
      PokedexText.unknownName,
    ]

    for text in texts {
      // CJK 統合漢字の範囲。受け入れ条件の「漢字を使わない」を機械的に確認する
      XCTAssertNil(
        text.unicodeScalars.first { (0x4E00...0x9FFF).contains($0.value) },
        "漢字が含まれています: \(text)"
      )
    }
  }

  @MainActor
  private func makeContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
      for: PokemonCacheEntry.self, CaughtPokemon.self,
      configurations: configuration
    )
  }

  @MainActor
  private func makeModel(
    container: ModelContainer,
    store: CaughtPokemonStore,
    pokemonIDs: [Int],
    dataSource: PokemonDataSourceStub = PokemonDataSourceStub(failingIDs: [])
  ) -> PokedexModel {
    PokedexModel(
      repository: PokemonRepository(
        modelContext: container.mainContext,
        dataSource: dataSource,
        pokemonIDs: pokemonIDs
      ),
      caughtPokemonStore: store,
      imageCache: nil
    )
  }
}

/// PokeAPI の代わりに架空のメタデータを返すテスト用データソース。
private actor PokemonDataSourceStub: PokemonDataSource {
  private let failingIDs: Set<Int>
  private var requests = 0

  init(failingIDs: Set<Int>) {
    self.failingIDs = failingIDs
  }

  func fetchPokemon(id: Int) async throws -> Pokemon {
    requests += 1

    if failingIDs.contains(id) {
      throw PokemonDataSourceStubError.requestedFailure(id)
    }

    return Pokemon(
      id: id,
      japaneseName: "テストモン\(id)",
      spriteURL: URL(string: "https://example.com/\(id).png")!
    )
  }

  func requestCount() -> Int {
    requests
  }
}

private enum PokemonDataSourceStubError: Error, Equatable {
  case requestedFailure(Int)
}
