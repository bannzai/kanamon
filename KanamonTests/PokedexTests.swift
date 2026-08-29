import Foundation
import SwiftData
import UIKit
import XCTest

@testable import Kanamon

final class PokedexTests: XCTestCase {
  func testYomiRenshuDestinationKeepsSelectedPokemonID() {
    XCTAssertEqual(YomiRenshuDestination(pokemonID: 25).pokemonID, 25)
    XCTAssertNotEqual(YomiRenshuDestination(pokemonID: 1), YomiRenshuDestination(pokemonID: 2))
  }

  func testNumberTextUsesThreeDigits() {
    XCTAssertEqual(pokedexNumberText(id: 1), "No.001")
    XCTAssertEqual(pokedexNumberText(id: 25), "No.025")
    XCTAssertEqual(pokedexNumberText(id: 151), "No.151")
  }

  @MainActor
  func testModelLoadsPokemonListWithCaughtStatus() async throws {
    let container = try makeContainer()
    let store = LearningProgressStore(modelContext: container.mainContext)
    try store.markPokemonCaught(id: 2)
    let model = makeModel(container: container, store: store, pokemonIDs: [1, 2, 3])

    await model.load()

    XCTAssertEqual(model.state, .loaded)
    XCTAssertEqual(model.pokemons.map(\.id), [1, 2, 3])
    XCTAssertFalse(model.isCaught(model.pokemons[0]))
    XCTAssertTrue(model.isCaught(model.pokemons[1]))
  }

  @MainActor
  func testModelProgressCountsOnlyPokemonShownInTheList() async throws {
    let container = try makeContainer()
    let store = LearningProgressStore(modelContext: container.mainContext)
    try store.markPokemonCaught(id: 1)
    try store.markPokemonCaught(id: 99)
    let model = makeModel(container: container, store: store, pokemonIDs: [1, 2, 3, 4])

    await model.load()

    XCTAssertEqual(model.caughtCount, 1)
    XCTAssertEqual(model.progressText, "1 / 4")
    XCTAssertEqual(model.progressFraction, 0.25)
  }

  @MainActor
  func testModelNumberRangeTextShowsFirstAndLastNumber() async throws {
    let container = try makeContainer()
    let model = makeModel(
      container: container,
      store: LearningProgressStore(modelContext: container.mainContext),
      pokemonIDs: [1, 2, 3]
    )
    XCTAssertEqual(model.numberRangeText, "No.--- - ---")
    XCTAssertEqual(model.progressFraction, 0)

    await model.load()

    XCTAssertEqual(model.numberRangeText, "No.001 - 003")
  }

  @MainActor
  func testModelReloadsCaughtStatusWithoutFetchingPokemonAgain() async throws {
    let container = try makeContainer()
    let store = LearningProgressStore(modelContext: container.mainContext)
    let dataSource = PokemonDataSourceStub(failingIDs: [])
    let model = makeModel(
      container: container,
      store: store,
      pokemonIDs: [1, 2, 3],
      dataSource: dataSource
    )
    await model.load()
    let requestCountAfterLoad = await dataSource.requestCount()

    try store.markPokemonCaught(id: 3)
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
      store: LearningProgressStore(modelContext: container.mainContext),
      pokemonIDs: [1, 2],
      dataSource: PokemonDataSourceStub(failingIDs: [2])
    )

    await model.load()

    XCTAssertEqual(model.state, .failed)
  }

  func testDisplayedTextsUseKanaOnly() {
    let texts = [
      PokedexText.title,
      PokedexDeviceText.title,
      PokedexText.caughtCountLabel,
      PokedexText.loading,
      PokedexText.failed,
      PokedexText.retry,
      PokedexDeviceText.back,
      PokedexText.unknownName,
      PokedexText.lockedToast,
    ]

    for text in texts {
      // CJK 統合漢字の範囲。受け入れ条件の「漢字を使わない」を機械的に確認する
      XCTAssertNil(
        text.unicodeScalars.first { (0x4E00...0x9FFF).contains($0.value) },
        "漢字が含まれています: \(text)"
      )
    }
  }

  func testDesignColorsMatchSpecificationHex() {
    // README「6. スタイルトークン」の 16 進値が Color(hex:) で正しく分解されることを、インクの色で確認する
    let ink = UIColor(DesignColor.ink)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    ink.getRed(&red, green: &green, blue: &blue, alpha: nil)

    XCTAssertEqual(red, 0x33 / 255.0, accuracy: 0.001)
    XCTAssertEqual(green, 0x24 / 255.0, accuracy: 0.001)
    XCTAssertEqual(blue, 0x1A / 255.0, accuracy: 0.001)
  }

  @MainActor
  private func makeContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
      for: PokemonCacheEntry.self, CaughtPokemonEntry.self, CharacterProgressEntry.self,
      configurations: configuration
    )
  }

  @MainActor
  private func makeModel(
    container: ModelContainer,
    store: LearningProgressStore,
    pokemonIDs: [Int],
    dataSource: PokemonDataSourceStub = PokemonDataSourceStub(failingIDs: [])
  ) -> PokedexModel {
    PokedexModel(
      repository: PokemonRepository(
        modelContext: container.mainContext,
        dataSource: dataSource,
        pokemonIDs: pokemonIDs
      ),
      learningProgressStore: store,
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
