import Foundation
import SwiftData
import XCTest

@testable import Kanamon

final class PokemonDataTests: XCTestCase {
  func testKatakanaConverterHandlesLongVowelsAndSmallKana() {
    XCTAssertEqual(KatakanaConverter.hiragana(from: "キョウリューッコ"), "きょうりゅーっこ")
  }

  func testKatakanaConverterIsIdempotentForHiragana() {
    let hiragana = "きょうりゅーっこ"

    XCTAssertEqual(KatakanaConverter.hiragana(from: hiragana), hiragana)
  }

  func testPokeAPIClientFetchesJapaneseNameAndSpriteURLUsingMockedNetwork() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { MockURLProtocol.handler = nil }
    MockURLProtocol.handler = { request in
      let data: Data
      if request.url?.path.contains("pokemon-species") == true {
        data = Data(#"{"names":[{"name":"テストモン","language":{"name":"ja"}}]}"#.utf8)
      } else {
        data = Data(#"{"id":1,"sprites":{"front_default":"https://example.com/test-sprite.png"}}"#.utf8)
      }
      let response = HTTPURLResponse(
        url: try XCTUnwrap(request.url),
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, data)
    }

    let client = PokeAPIClient(session: session)
    let pokemon = try await client.fetchPokemon(id: 1)

    XCTAssertEqual(pokemon.id, 1)
    XCTAssertEqual(pokemon.japaneseName, "テストモン")
    XCTAssertEqual(pokemon.spriteURL.absoluteString, "https://example.com/test-sprite.png")
  }

  @MainActor
  func testRepositoryFetchesOnCacheMissAndUsesSwiftDataOnCacheHit() async throws {
    let container = try makeContainer()
    let dataSource = PokemonDataSourceStub(
      pokemonByID: [
        1: Pokemon(
          id: 1,
          japaneseName: "テストモン",
          spriteURL: URL(string: "https://example.com/1.png")!
        ),
        2: Pokemon(
          id: 2,
          japaneseName: "サンプルン",
          spriteURL: URL(string: "https://example.com/2.png")!
        ),
      ]
    )
    let repository = PokemonRepository(
      modelContext: ModelContext(container),
      dataSource: dataSource,
      pokemonIDs: [1, 2]
    )

    let firstLoad = try await repository.loadFirstGeneration()
    let secondLoad = try await repository.loadFirstGeneration()
    let requestedIDs = await dataSource.requestedIDs()

    XCTAssertEqual(firstLoad, secondLoad)
    XCTAssertEqual(Set(requestedIDs), [1, 2])
  }

  @MainActor
  func testRepositoryFetchesOnlyMissingMetadata() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    context.insert(
      PokemonCacheEntry(
        pokemon: Pokemon(
          id: 1,
          japaneseName: "キャッシュモン",
          spriteURL: URL(string: "https://example.com/cached.png")!
        )
      )
    )
    try context.save()
    let dataSource = PokemonDataSourceStub(
      pokemonByID: [
        2: Pokemon(
          id: 2,
          japaneseName: "ミスモン",
          spriteURL: URL(string: "https://example.com/missing.png")!
        )
      ]
    )
    let repository = PokemonRepository(
      modelContext: context,
      dataSource: dataSource,
      pokemonIDs: [1, 2]
    )

    let pokemon = try await repository.loadFirstGeneration()
    let requestedIDs = await dataSource.requestedIDs()

    XCTAssertEqual(pokemon.map(\.id), [1, 2])
    XCTAssertEqual(requestedIDs, [2])
  }

  @MainActor
  func testRepositoryLimitsConcurrentMetadataRequests() async throws {
    let container = try makeContainer()
    let dataSource = PokemonDataSourceStub(
      pokemonByID: Dictionary(uniqueKeysWithValues: (1...4).map { ($0, makePokemon(id: $0)) }),
      delayMilliseconds: 30
    )
    let repository = PokemonRepository(
      modelContext: ModelContext(container),
      dataSource: dataSource,
      pokemonIDs: Array(1...4),
      maximumConcurrentRequests: 2
    )

    _ = try await repository.loadFirstGeneration()
    let maximumActiveRequests = await dataSource.maximumActiveRequestCount()

    XCTAssertEqual(maximumActiveRequests, 2)
  }

  @MainActor
  func testRepositoryKeepsSuccessfulMetadataWhenLaterRequestFails() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let dataSource = PokemonDataSourceStub(
      pokemonByID: [1: makePokemon(id: 1), 2: makePokemon(id: 2)],
      failingIDs: [2]
    )
    let repository = PokemonRepository(
      modelContext: context,
      dataSource: dataSource,
      pokemonIDs: [1, 2],
      maximumConcurrentRequests: 1
    )

    do {
      _ = try await repository.loadFirstGeneration()
      XCTFail("2件目の取得エラーが返る必要があります")
    } catch {
      XCTAssertEqual(error as? PokemonDataSourceStubError, .requestedFailure(2))
    }

    let savedEntries = try context.fetch(
      FetchDescriptor<PokemonCacheEntry>(sortBy: [SortDescriptor(\PokemonCacheEntry.pokemonID)])
    )
    XCTAssertEqual(savedEntries.map(\.pokemonID), [1])
  }

  func testImageCacheDownloadsOnMissAndReadsFileOnHit() async throws {
    let directory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("tmp", isDirectory: true)
      .appendingPathComponent("PokemonImageCacheTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let expectedData = Data([0x01, 0x02, 0x03])
    let dataLoader = HTTPDataLoaderStub(data: expectedData)
    let cache = try PokemonImageCache(cacheDirectory: directory, dataLoader: dataLoader)
    let pokemon = Pokemon(
      id: 1,
      japaneseName: "テストモン",
      spriteURL: URL(string: "https://example.com/test-sprite.png")!
    )

    let firstLoad = try await cache.imageData(for: pokemon)
    let secondLoad = try await cache.imageData(for: pokemon)
    let requestCount = await dataLoader.requestCount()

    XCTAssertEqual(firstLoad, expectedData)
    XCTAssertEqual(secondLoad, expectedData)
    XCTAssertEqual(requestCount, 1)
  }

  func testImageCacheSharesConcurrentDownloadForSamePokemon() async throws {
    let directory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("tmp", isDirectory: true)
      .appendingPathComponent("PokemonImageCacheConcurrentTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let expectedData = Data([0x04, 0x05, 0x06])
    let dataLoader = HTTPDataLoaderStub(data: expectedData, delayMilliseconds: 30)
    let cache = try PokemonImageCache(cacheDirectory: directory, dataLoader: dataLoader)
    let pokemon = makePokemon(id: 1)

    async let firstLoad = cache.imageData(for: pokemon)
    async let secondLoad = cache.imageData(for: pokemon)
    let (firstData, secondData) = try await (firstLoad, secondLoad)
    let requestCount = await dataLoader.requestCount()

    XCTAssertEqual(firstData, expectedData)
    XCTAssertEqual(secondData, expectedData)
    XCTAssertEqual(requestCount, 1)
  }

  @MainActor
  private func makeContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: PokemonCacheEntry.self, configurations: configuration)
  }
}

/// PokeAPI の代わりに架空のメタデータを返すテスト用データソース。
private actor PokemonDataSourceStub: PokemonDataSource {
  private let pokemonByID: [Int: Pokemon]
  private let failingIDs: Set<Int>
  private let delayMilliseconds: Int
  private var requests: [Int] = []
  private var activeRequests = 0
  private var maximumActiveRequests = 0

  init(
    pokemonByID: [Int: Pokemon],
    failingIDs: Set<Int> = [],
    delayMilliseconds: Int = 0
  ) {
    self.pokemonByID = pokemonByID
    self.failingIDs = failingIDs
    self.delayMilliseconds = delayMilliseconds
  }

  func fetchPokemon(id: Int) async throws -> Pokemon {
    requests.append(id)
    activeRequests += 1
    maximumActiveRequests = max(maximumActiveRequests, activeRequests)
    defer { activeRequests -= 1 }

    if delayMilliseconds > 0 {
      try await ContinuousClock().sleep(for: .milliseconds(delayMilliseconds))
    }
    if failingIDs.contains(id) {
      throw PokemonDataSourceStubError.requestedFailure(id)
    }
    return try XCTUnwrap(pokemonByID[id])
  }

  func requestedIDs() -> [Int] {
    requests
  }

  func maximumActiveRequestCount() -> Int {
    maximumActiveRequests
  }
}

private enum PokemonDataSourceStubError: Error, Equatable {
  case requestedFailure(Int)
}

/// URLProtocol を使わずに画像取得結果を返すテスト用ローダー。
private actor HTTPDataLoaderStub: HTTPDataLoading {
  private let responseData: Data
  private let delayMilliseconds: Int
  private var requests = 0

  init(data: Data, delayMilliseconds: Int = 0) {
    responseData = data
    self.delayMilliseconds = delayMilliseconds
  }

  func data(from url: URL) async throws -> (Data, URLResponse) {
    requests += 1
    if delayMilliseconds > 0 {
      try await ContinuousClock().sleep(for: .milliseconds(delayMilliseconds))
    }
    let response = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    return (responseData, response)
  }

  func requestCount() -> Int {
    requests
  }
}

private func makePokemon(id: Int) -> Pokemon {
  Pokemon(
    id: id,
    japaneseName: "テストモン\(id)",
    spriteURL: URL(string: "https://example.com/\(id).png")!
  )
}

/// PokeAPI クライアントの通信をプロセス内で差し替える URLProtocol。
private final class MockURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
