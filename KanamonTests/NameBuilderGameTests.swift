import SwiftData
import XCTest

@testable import Kanamon

/// 実在のポケモン名・画像はテストにも置かないため (`.claude/rules/pokemon-assets-no-commit.md`)、
/// 架空の名前で判定ロジックを検証する。
final class NameBuilderGameTests: XCTestCase {
  func testCorrectOrderIsAccepted() {
    var game = NameBuilderGame(answer: Array("テストモン"), tiles: Array("モテンスト"))
    for character in "テストモン" {
      place(character: character, in: &game)
    }

    XCTAssertEqual(game.placed, Array("テストモン"))
    XCTAssertEqual(game.judgement(), .correct)
  }

  func testWrongOrderKeepsMatchingPrefix() {
    var game = NameBuilderGame(answer: Array("テストモン"), tiles: Array("テスモンヌ"))
    for character in "テスモンヌ" {
      place(character: character, in: &game)
    }

    XCTAssertEqual(game.judgement(), .rollback(keepCount: 2))
    game.rollback(keepCount: 2)
    XCTAssertEqual(game.placed, Array("テス"))
  }

  /// 先頭から 1 文字も合っていない時は空に戻す。
  func testWrongOrderWithoutMatchingPrefixClearsAll() {
    var game = NameBuilderGame(answer: Array("テスト"), tiles: Array("テスト"))
    for character in "トステ" {
      place(character: character, in: &game)
    }

    XCTAssertEqual(game.judgement(), .rollback(keepCount: 0))
    game.rollback(keepCount: 0)
    XCTAssertTrue(game.placed.isEmpty)
  }

  /// 同じ文字が名前に 2 回出る場合、使用済みフラグではなく使用回数でタイルを管理する。
  func testRepeatedCharacterUsesTileCount() {
    var game = NameBuilderGame(answer: Array("モモンガ"), tiles: Array("モモンガヌ"))

    place(character: "モ", in: &game)
    XCTAssertEqual(game.tileStates.filter { $0.character == "モ" && $0.isSpent }.count, 1)
    XCTAssertEqual(game.tileStates.filter { $0.character == "モ" && !$0.isSpent }.count, 1)

    place(character: "モ", in: &game)
    XCTAssertTrue(game.tileStates.filter { $0.character == "モ" }.allSatisfy(\.isSpent))

    place(character: "ン", in: &game)
    place(character: "ガ", in: &game)
    XCTAssertEqual(game.placed, Array("モモンガ"))
    XCTAssertEqual(game.judgement(), .correct)
  }

  /// 同じ文字が 2 回出る名前を、2 文字目だけ間違えた時も先頭の 1 文字は残す。
  func testRepeatedCharacterKeepsMatchingPrefix() {
    var game = NameBuilderGame(answer: Array("モモンガ"), tiles: Array("モモンガ"))
    for character in "モンモガ" {
      place(character: character, in: &game)
    }

    XCTAssertEqual(game.judgement(), .rollback(keepCount: 1))
    game.rollback(keepCount: 1)
    XCTAssertEqual(game.placed, ["モ"])
  }

  /// 同じ文字のタイルが 2 枚ある時、タップした側だけが薄くなる。
  func testRepeatedCharacterMarksTappedTileAsSpent() {
    var game = NameBuilderGame(answer: Array("モモンガ"), tiles: Array("モンモガ"))
    guard let secondMo = game.tileStates.last(where: { $0.character == "モ" }) else {
      return XCTFail("モ のタイルが見つからない")
    }

    game.place(tile: secondMo)
    XCTAssertEqual(game.tileStates.filter(\.isSpent).map(\.id), [secondMo.id])
    XCTAssertEqual(game.placed, ["モ"])
  }

  /// 同じタイルの値で 2 回続けて置いても、1 枚ぶんしか置けない。
  ///
  /// `Tile.isSpent` は表示を組み立てた時点の値のため、素早く 2 回叩くと同じ値が 2 回渡る。
  func testPlacingSameTileValueTwiceAddsOneCharacter() {
    var game = NameBuilderGame(answer: Array("テスト"), tiles: Array("テスト"))
    guard let tile = game.tileStates.first(where: { $0.character == "テ" }) else {
      return XCTFail("テ のタイルが見つからない")
    }

    game.place(tile: tile)
    game.place(tile: tile)
    XCTAssertEqual(game.placed, ["テ"])
  }

  /// タイルが 1 枚しかない文字は、1 回置いた時点で押せなくなる。
  func testSpentTileCannotBePlacedAgain() {
    var game = NameBuilderGame(answer: Array("テスト"), tiles: Array("テスト"))
    place(character: "テ", in: &game)

    guard let spentTile = game.tileStates.first(where: { $0.character == "テ" }) else {
      return XCTFail("テ のタイルが見つからない")
    }
    XCTAssertTrue(spentTile.isSpent)

    game.place(tile: spentTile)
    XCTAssertEqual(game.placed, ["テ"])
  }

  func testJudgementIsNilWhileSlotsRemain() {
    var game = NameBuilderGame(answer: Array("テスト"), tiles: Array("テスト"))
    place(character: "テ", in: &game)

    XCTAssertFalse(game.isFilled)
    XCTAssertNil(game.judgement())
  }

  func testUndoRemovesLastCharacter() {
    var game = NameBuilderGame(answer: Array("テスト"), tiles: Array("テスト"))
    place(character: "テ", in: &game)
    place(character: "ス", in: &game)

    game.undo()
    XCTAssertEqual(game.placed, ["テ"])

    game.undo()
    game.undo()
    XCTAssertTrue(game.placed.isEmpty)
  }

  /// 埋めたマスをタップすると、そこから後ろがまとめて消える。
  func testRemovePlacedDropsFollowingCharacters() {
    var game = NameBuilderGame(answer: Array("テストモン"), tiles: Array("テストモン"))
    for character in "テスト" {
      place(character: character, in: &game)
    }

    game.removePlaced(index: 1)
    XCTAssertEqual(game.placed, ["テ"])

    game.removePlaced(index: 1)
    XCTAssertEqual(game.placed, ["テ"], "範囲外のマスをタップしても変化しない")
  }

  /// 間違えた並びを戻すまでの間にタイルをタップしても、並びは変わらない。
  func testPlaceIsIgnoredWhileWrongOrderRemainsFilled() {
    var game = NameBuilderGame(answer: Array("テスト"), tiles: Array("テストヌ"))
    for character in "テトス" {
      place(character: character, in: &game)
    }
    XCTAssertEqual(game.judgement(), .rollback(keepCount: 1))

    guard let tile = game.tileStates.first(where: { $0.character == "ヌ" }) else {
      return XCTFail("ヌ のタイルが見つからない")
    }
    game.place(tile: tile)
    XCTAssertEqual(game.placed, Array("テトス"))
  }

  func testPlaceIsIgnoredWhenAllSlotsAreFilled() {
    var game = NameBuilderGame(answer: Array("テス"), tiles: Array("テスト"))
    place(character: "テ", in: &game)
    place(character: "ス", in: &game)
    place(character: "ト", in: &game)

    XCTAssertEqual(game.placed, ["テ", "ス"])
  }

  func testTilesContainAnswerAndDecoys() {
    let answer = Array("テスト")
    var generator = SeededGenerator(seed: 42)
    let tiles = NameBuilderTileMaker.tiles(answer: answer, generator: &generator)

    XCTAssertEqual(tiles.count, answer.count + NameBuilderTileMaker.decoyCount(answerLength: answer.count))
    for character in answer {
      XCTAssertEqual(
        tiles.filter { $0 == character }.count,
        answer.filter { $0 == character }.count,
        "\(character) のタイルの枚数が名前に出る回数と合っていない"
      )
    }
    for decoy in tiles where !answer.contains(decoy) {
      XCTAssertTrue(Gojuon.characters.contains(decoy), "\(decoy) が五十音表の 46 文字に含まれていない")
    }
  }

  /// 似ている文字の選び分けを練習にするため、形の似た文字をダミーに優先して混ぜる。
  func testTilesPreferSimilarCharactersAsDecoys() {
    var generator = SeededGenerator(seed: 7)
    let tiles = NameBuilderTileMaker.tiles(answer: Array("シ"), generator: &generator)

    XCTAssertTrue(tiles.contains("ツ"), "シ に似ている ツ がダミーに入っていない")
  }

  func testDecoyCountStaysBetweenThreeAndSix() {
    for answerLength in 1...12 {
      let count = NameBuilderTileMaker.decoyCount(answerLength: answerLength)
      XCTAssertGreaterThanOrEqual(count, 3)
      XCTAssertLessThanOrEqual(count, 6)
    }
  }

  /// 誤った並びを戻すまでの間は、盤面のタップを受け付けない。
  ///
  /// 受け付けると、古い判定の戻し先が新しい並びへ適用されてしまう。
  @MainActor
  func testModelIgnoresInputWhileRollingBack() async throws {
    let context = ModelContext(try makeContainer())
    let model = makeModel(context: context)
    await model.load()

    let answer = try XCTUnwrap(model.game?.answer)
    for character in answer.reversed() {
      _ = model.place(tile: try tile(character: character, in: model))
    }

    XCTAssertFalse(model.acceptsInput)
    let placedWhileRollingBack = try XCTUnwrap(model.game?.placed)
    model.undo()
    model.removePlaced(index: 0)
    // 正解の文字はすべて置いた後なので、まだ使っていないダミーのタイルで試す。
    _ = model.place(tile: try XCTUnwrap(model.game?.tileStates.first { !$0.isSpent }))
    XCTAssertEqual(model.game?.placed, placedWhileRollingBack)

    model.rollback(keepCount: 0)
    XCTAssertTrue(model.acceptsInput)
    XCTAssertEqual(model.game?.placed, [])
  }

  /// 正解した後もゲット演出の間はタップを受け付けない。
  @MainActor
  func testModelIgnoresInputAfterCorrectAnswer() async throws {
    let context = ModelContext(try makeContainer())
    let model = makeModel(context: context)
    await model.load()

    let answer = try XCTUnwrap(model.game?.answer)
    for character in answer {
      _ = model.place(tile: try tile(character: character, in: model))
    }

    XCTAssertEqual(model.result?.isNewCatch, true)
    XCTAssertFalse(model.acceptsInput)
    model.undo()
    XCTAssertEqual(model.game?.placed, answer)
  }

  /// 正解すると、名前に含まれる文字が読めた文字として記録される。
  @MainActor
  func testModelRecordsReadCharactersOnCorrectAnswer() async throws {
    let context = ModelContext(try makeContainer())
    let store = LearningProgressStore(modelContext: context)
    let model = makeModel(context: context, store: store)
    await model.load()

    let answer = try XCTUnwrap(model.game?.answer)
    for character in answer {
      _ = model.place(tile: try tile(character: character, in: model))
    }

    XCTAssertEqual(try store.caughtPokemonIDs(), [1])
    XCTAssertEqual(try store.readCharacters(), Gojuon.readableCharacters(in: String(answer)))
  }

  /// 画面を離れた時の取り消しを、読み込みの失敗として扱わない。
  @MainActor
  func testModelDoesNotFailOnCancellation() async throws {
    let context = ModelContext(try makeContainer())
    let model = makeModel(context: context)

    let task = Task { await model.load() }
    task.cancel()
    await task.value

    XCTAssertNotEqual(model.state, .failed)
  }

  /// 子どもが読めるように、画面に出す文言はかな・数字・約物だけにする。
  func testNameBuilderTextUsesOnlyReadableCharacters() {
    for text in NameBuilderText.all {
      XCTAssertTrue(text.isNameBuilderReadable, "\(text) に かな 以外の文字が含まれている")
    }
  }

  /// 画面のタップと同じ経路で 1 文字置く。使い切っていないタイルを `tileStates` から選ぶ。
  private func place(character: Character, in game: inout NameBuilderGame) {
    guard let tile = game.tileStates.first(where: { $0.character == character && !$0.isSpent }) else {
      return XCTFail("\(character) の使えるタイルが見つからない")
    }
    game.place(tile: tile)
  }

  @MainActor
  private func tile(character: Character, in model: NameBuilderModel) throws -> NameBuilderGame.Tile {
    try XCTUnwrap(
      model.game?.tileStates.first { $0.character == character && !$0.isSpent },
      "\(character) の使えるタイルが見つからない"
    )
  }

  @MainActor
  private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
      for: PokemonCacheEntry.self, CaughtPokemonEntry.self, CharacterProgressEntry.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
  }

  @MainActor
  private func makeModel(context: ModelContext, store: LearningProgressStore? = nil) -> NameBuilderModel {
    let pokemon = Pokemon(
      id: 1,
      japaneseName: "テストモン",
      spriteURL: URL(string: "https://example.invalid/1.png")!
    )
    return NameBuilderModel(
      repository: PokemonRepository(
        modelContext: context,
        dataSource: NameBuilderPokemonDataSourceStub(pokemonByID: [pokemon.id: pokemon]),
        pokemonIDs: [pokemon.id]
      ),
      learningProgressStore: store ?? LearningProgressStore(modelContext: context),
      imageCache: nil
    )
  }
}

/// PokeAPI の代わりに架空のメタデータを返すテスト用データソース。
///
/// 他のテストファイルの同種のスタブは `private` で使えないため、ここで用意する。
private actor NameBuilderPokemonDataSourceStub: PokemonDataSource {
  private let pokemonByID: [Int: Pokemon]

  init(pokemonByID: [Int: Pokemon]) {
    self.pokemonByID = pokemonByID
  }

  func fetchPokemon(id: Int) async throws -> Pokemon {
    try XCTUnwrap(pokemonByID[id])
  }
}

/// 出題のシャッフルを固定するための乱数生成器。
private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return state
  }
}

extension String {
  /// ひらがな・カタカナ (長音符・中黒を含む)・半角スペース・数字・全角の ！ ？ だけで構成されているか。
  fileprivate var isNameBuilderReadable: Bool {
    unicodeScalars.allSatisfy { scalar in
      (0x3041...0x309F).contains(scalar.value)
        || (0x30A0...0x30FF).contains(scalar.value)
        || (0x30...0x39).contains(scalar.value)
        || scalar.value == 0x20
        || scalar.value == 0xFF01
        || scalar.value == 0xFF1F
    }
  }
}
