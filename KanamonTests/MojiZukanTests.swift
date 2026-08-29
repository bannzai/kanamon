import CoreGraphics
import Foundation
import SwiftData
import SwiftUI
import XCTest

@testable import Kanamon

final class MojiZukanTests: XCTestCase {
  /// 表に並ぶ文字は `KatakanaGojuon` を正とし、配置だけを `GojuonTable` が持つ。
  func testGojuonTableLaysOutTheKatakanaGojuonInTenRowsOfFiveColumns() {
    XCTAssertEqual(GojuonTable.rows.count, 10)
    for row in GojuonTable.rows {
      XCTAssertEqual(row.count, GojuonTable.columnCount)
    }
    XCTAssertEqual(GojuonTable.cells.compactMap { $0 }, KatakanaGojuon.characters)
    XCTAssertEqual(KatakanaGojuon.characters.count, 46)
  }

  /// ヤ行・ワ行のイ段・エ段は空きマスにして、表の形を崩さずに 46 文字を並べる。
  func testGojuonTableLeavesBlankCellsInYaAndWaRows() {
    XCTAssertEqual(GojuonTable.rows[7].map { $0.map(String.init) }, ["ヤ", nil, "ユ", nil, "ヨ"])
    XCTAssertEqual(GojuonTable.rows[9].map { $0.map(String.init) }, ["ワ", nil, "ヲ", nil, "ン"])
    XCTAssertEqual(GojuonTable.cells.count, 50)
    XCTAssertEqual(GojuonTable.cells.filter { $0 == nil }.count, 4)
  }

  /// 濁点・半濁点・小書き文字を含む名前も、基底文字で逆引きできるようにする。
  func testPokemonCharacterSearchFindsVoicedAndSmallCharacters() {
    let pokemon = [
      Pokemon(id: 1, japaneseName: "ピカモン", spriteURL: sampleSpriteURL(id: 1)),
      Pokemon(id: 2, japaneseName: "ガッツモン", spriteURL: sampleSpriteURL(id: 2)),
      Pokemon(id: 3, japaneseName: "キョロモン", spriteURL: sampleSpriteURL(id: 3)),
    ]

    XCTAssertEqual(PokemonCharacterSearch.pokemon(containing: "ヒ", in: pokemon).map(\.id), [1])
    XCTAssertEqual(PokemonCharacterSearch.pokemon(containing: "ツ", in: pokemon).map(\.id), [2])
    XCTAssertEqual(PokemonCharacterSearch.pokemon(containing: "ヨ", in: pokemon).map(\.id), [3])
    XCTAssertEqual(PokemonCharacterSearch.pokemon(containing: "モ", in: pokemon).map(\.id), [1, 2, 3])
    XCTAssertEqual(PokemonCharacterSearch.pokemon(containing: "ヌ", in: pokemon).map(\.id), [])
  }

  /// 探している文字が名前のどこにいるかを、正規化した上で位置ごとに示す。
  func testNameCharactersMarkNormalizedMatchesWithTheirPosition() {
    let pokemon = Pokemon(id: 1, japaneseName: "ガッツモン", spriteURL: sampleSpriteURL(id: 1))

    XCTAssertEqual(
      PokemonCharacterSearch.nameCharacters(pokemon: pokemon, highlighting: "ツ"),
      [
        NameCharacter(id: 0, character: "ガ", isMatch: false),
        NameCharacter(id: 1, character: "ッ", isMatch: true),
        NameCharacter(id: 2, character: "ツ", isMatch: true),
        NameCharacter(id: 3, character: "モ", isMatch: false),
        NameCharacter(id: 4, character: "ン", isMatch: false),
      ]
    )
    XCTAssertEqual(
      PokemonCharacterSearch.nameCharacters(pokemon: pokemon, highlighting: "カ").map(\.isMatch),
      [true, false, false, false, false]
    )
  }

  /// 名前のどこが該当文字かを、色ではなく読み上げでも伝えられるようにする。
  func testMatchPositionsDescribesWhereTheCharacterAppears() {
    XCTAssertEqual(MojiZukanText.matchPositions(character: "カ", positions: [3]), "カ は 3 ばんめ")
    XCTAssertEqual(
      MojiZukanText.matchPositions(character: "ツ", positions: [2, 3]),
      "ツ は 2 ばんめ と 3 ばんめ"
    )
    XCTAssertEqual(MojiZukanText.matchPositions(character: "ヌ", positions: []), "")
  }

  /// 子どもが読めるように、画面に出す文言は漢字を使わずひらがな・カタカナだけで書く。
  func testMojiZukanTextsUseNoKanji() {
    let texts =
      MojiZukanText.all + [
        MojiZukanText.sheetTitle(character: "ア"),
        MojiZukanText.pokemonCount(count: 3),
        MojiZukanText.matchPositions(character: "カ", positions: [3]),
      ]
    for text in texts {
      XCTAssertFalse(text.containsKanji, "\(text) に漢字が含まれている")
    }
  }

  @MainActor
  func testViewsCanBeInstantiated() {
    XCTAssertNotNil(MojiZukanView(path: .constant(NavigationPath())).body)
  }

  /// 画面の狭い端末でも、五十音のマスが子ども向けの最小タップ領域 60pt を下回らないようにする。
  func testGojuonCellStaysAtLeastMinimumTapTarget() {
    // iPhone SE (幅 375pt) から図鑑筐体の左右の余白 (12pt × 2) を引いた画面の幅
    let smallestScreenWidth: CGFloat = 375 - 24

    XCTAssertGreaterThanOrEqual(GojuonLayout.cellWidth(screenWidth: smallestScreenWidth), 60)
    XCTAssertGreaterThanOrEqual(
      GojuonLayout.cellWidth(screenWidth: PokedexLayout.maximumScreenWidth - 24),
      60
    )
  }

  /// よみれんしゅう等から戻った時に、表と進捗が追随するようにする。
  @MainActor
  func testReloadProgressPicksUpCharactersReadAfterLoading() async throws {
    let modelContext = ModelContext(PersistenceController(isStoredInMemoryOnly: true).container)
    let learningProgressStore = LearningProgressStore(modelContext: modelContext)
    let model = MojiZukanModel(
      repository: PokemonRepository(
        modelContext: modelContext,
        dataSource: StubPokemonDataSource(),
        pokemonIDs: []
      ),
      learningProgressStore: learningProgressStore,
      imageCache: nil
    )
    await model.load()
    XCTAssertEqual(model.readCount, 0)

    try learningProgressStore.markRead(character: "ア")
    model.reloadProgress()

    XCTAssertEqual(model.readCount, 1)
    XCTAssertTrue(model.isRead("ア"))
  }

  /// 進捗の分子には五十音表に並ぶ 46 文字だけを数え、長音符などは数えない。
  @MainActor
  func testReadCountCountsOnlyCharactersOnTheGojuon() async throws {
    let modelContext = ModelContext(PersistenceController(isStoredInMemoryOnly: true).container)
    let learningProgressStore = LearningProgressStore(modelContext: modelContext)
    try learningProgressStore.markRead(character: "ア")
    try learningProgressStore.markRead(character: "ー")

    let model = MojiZukanModel(
      repository: PokemonRepository(
        modelContext: modelContext,
        dataSource: StubPokemonDataSource(),
        pokemonIDs: []
      ),
      learningProgressStore: learningProgressStore,
      imageCache: nil
    )
    await model.load()

    XCTAssertEqual(model.readCount, 1)
    XCTAssertEqual(model.progressText, "1 / 46")
  }

  /// 逆引きシートは読み込みの完了より先に開けるため、読み込み後の一覧をモデル経由で見られるようにする。
  @MainActor
  func testModelExposesProgressAndReverseLookupAfterLoading() async throws {
    let modelContext = ModelContext(PersistenceController(isStoredInMemoryOnly: true).container)
    let learningProgressStore = LearningProgressStore(modelContext: modelContext)
    try learningProgressStore.markRead(character: "ピ")
    try learningProgressStore.markPokemonCaught(id: 1)

    let model = MojiZukanModel(
      repository: PokemonRepository(
        modelContext: modelContext,
        dataSource: StubPokemonDataSource(),
        pokemonIDs: [1, 2]
      ),
      learningProgressStore: learningProgressStore,
      imageCache: nil
    )
    await model.load()

    XCTAssertEqual(model.state, .loaded)
    XCTAssertEqual(model.progressText, "1 / 46")
    XCTAssertEqual(model.readCount, 1)
    XCTAssertTrue(model.isRead("ヒ"))
    XCTAssertEqual(model.pokemons(containing: "ヒ").map(\.id), [1])
    XCTAssertTrue(model.isCaught(model.pokemons[0]))
    XCTAssertFalse(model.isCaught(model.pokemons[1]))
  }

  private func sampleSpriteURL(id: Int) -> URL {
    URL(string: "https://example.com/\(id).png")!
  }
}

extension String {
  /// CJK 統合漢字 (U+4E00-U+9FFF) を含むか。
  fileprivate var containsKanji: Bool {
    unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
  }
}

/// 実在のポケモンを使わずに逆引きを検証するための、架空の名前を返すデータソース。
private struct StubPokemonDataSource: PokemonDataSource {
  func fetchPokemon(id: Int) async throws -> Pokemon {
    Pokemon(
      id: id,
      japaneseName: id == 1 ? "ピカモン" : "ヌルモン",
      spriteURL: URL(string: "https://example.com/\(id).png")!
    )
  }
}
