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
    XCTAssertEqual(game.judgement(), .correct)
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

  func testTilesMixAnswerAndDecoys() {
    let answer = Array("テスト")
    let tiles = NameBuilderTileMaker.tiles(answer: answer, shuffle: { $0 })

    XCTAssertEqual(tiles.count, answer.count + NameBuilderTileMaker.decoyCount(answerLength: answer.count))
    XCTAssertEqual(Array(tiles.prefix(answer.count)), answer, "シャッフルを恒等関数にすると正解の文字が先に並ぶ")
    for decoy in tiles.dropFirst(answer.count) {
      XCTAssertFalse(answer.contains(decoy), "\(decoy) が正解の文字と重複している")
      XCTAssertTrue(KatakanaSyllabary.characters.contains(decoy), "\(decoy) が五十音の 46 文字に含まれていない")
    }
  }

  func testDecoyCountStaysBetweenThreeAndSix() {
    for answerLength in 1...12 {
      let count = NameBuilderTileMaker.decoyCount(answerLength: answerLength)
      XCTAssertGreaterThanOrEqual(count, 3)
      XCTAssertLessThanOrEqual(count, 6)
    }
  }

  func testSyllabaryHasFortySixCharacters() {
    XCTAssertEqual(KatakanaSyllabary.characters.count, 46)
    XCTAssertEqual(Set(KatakanaSyllabary.characters).count, 46)
  }

  /// 画面のタップと同じ経路で 1 文字置く。使い切っていないタイルを `tileStates` から選ぶ。
  private func place(character: Character, in game: inout NameBuilderGame) {
    guard let tile = game.tileStates.first(where: { $0.character == character && !$0.isSpent }) else {
      return XCTFail("\(character) の使えるタイルが見つからない")
    }
    game.place(tile: tile)
  }
}
