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
