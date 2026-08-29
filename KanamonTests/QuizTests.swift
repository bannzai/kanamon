import Foundation
import SwiftData
import XCTest

@testable import Kanamon

final class QuizTests: XCTestCase {
  func testQuizModeCyclesThroughThreeModes() {
    XCTAssertEqual(QuizMode.allCases.count, 3)
    XCTAssertEqual(QuizMode.nameChoice.next, .fillInBlank)
    XCTAssertEqual(QuizMode.fillInBlank.next, .imageChoice)
    XCTAssertEqual(QuizMode.imageChoice.next, .nameChoice)
  }

  func testGojuonHasFortySixCharacters() {
    XCTAssertEqual(Gojuon.characters.count, 46)
    XCTAssertEqual(Set(Gojuon.characters).count, 46)
  }

  func testReadableCharactersKeepOnlyNormalizedGojuonCharacters() {
    XCTAssertEqual(Gojuon.readableCharacters(in: "テストモン"), ["テ", "ス", "ト", "モ", "ン"])
    XCTAssertEqual(Gojuon.readableCharacters(in: "ダミーゴン"), ["タ", "ミ", "コ", "ン"])
    XCTAssertEqual(Gojuon.readableCharacters(in: "ピョッコ"), ["ヒ", "ヨ", "ツ", "コ"])
  }

  func testPokemonChoicesAreFourUniqueAndContainAnswer() {
    let pokemons = (1...12).map(makePokemon(id:))

    for seed in UInt64(1)...5 {
      var questionGenerator = QuizQuestionGenerator(
        pokemons: pokemons,
        caughtPokemonIDs: [],
        generator: SeededGenerator(seed: seed)
      )

      for mode in [QuizMode.nameChoice, .imageChoice] {
        for _ in 0..<50 {
          guard let question = questionGenerator.makeQuestion(mode: mode) else {
            XCTFail("12 匹あれば出題できる必要があります")
            return
          }

          XCTAssertEqual(question.pokemonChoices.count, 4)
          XCTAssertEqual(Set(question.pokemonChoices.map(\.id)).count, 4)
          XCTAssertTrue(question.pokemonChoices.contains(question.answer))
          XCTAssertNil(question.blankIndex)
          XCTAssertTrue(question.kanaChoices.isEmpty)
        }
      }
    }
  }

  func testFillInBlankChoicesContainCorrectKanaAndSkipLongVowel() throws {
    let pokemons = (1...12).map(makePokemon(id:))

    for seed in UInt64(1)...5 {
      var questionGenerator = QuizQuestionGenerator(
        pokemons: pokemons,
        caughtPokemonIDs: [],
        generator: SeededGenerator(seed: seed)
      )

      for _ in 0..<50 {
        let question = try XCTUnwrap(questionGenerator.makeQuestion(mode: .fillInBlank))
        let characters = Array(question.answer.japaneseName)
        let blankIndex = try XCTUnwrap(question.blankIndex)

        XCTAssertTrue(characters.indices.contains(blankIndex))
        XCTAssertNotEqual(characters[blankIndex], "ー")
        XCTAssertEqual(question.kanaChoices.count, 4)
        XCTAssertEqual(Set(question.kanaChoices).count, 4)
        XCTAssertTrue(question.kanaChoices.contains(characters[blankIndex]))
        XCTAssertTrue(question.pokemonChoices.isEmpty)
      }
    }
  }

  func testFillInBlankNeverHidesSymbolsOrLongVowel() throws {
    let pokemons = (1...4).map { id in
      Pokemon(id: id, japaneseName: "テスト♀ー", spriteURL: URL(string: "https://example.com/\(id).png")!)
    }
    var questionGenerator = QuizQuestionGenerator(
      pokemons: pokemons,
      caughtPokemonIDs: [],
      generator: SeededGenerator(seed: 7)
    )

    for _ in 0..<50 {
      let question = try XCTUnwrap(questionGenerator.makeQuestion(mode: .fillInBlank))
      let hidden = Array(question.answer.japaneseName)[try XCTUnwrap(question.blankIndex)]
      XCTAssertTrue(["テ", "ス", "ト"].contains(hidden), "\(hidden) は穴にできない文字です")
    }
  }

  func testFillInBlankMixesSimilarCharacterIntoChoices() throws {
    let pokemons = (1...4).map { id in
      Pokemon(id: id, japaneseName: "シ", spriteURL: URL(string: "https://example.com/\(id).png")!)
    }
    var questionGenerator = QuizQuestionGenerator(
      pokemons: pokemons,
      caughtPokemonIDs: [],
      generator: SeededGenerator(seed: 11)
    )

    for _ in 0..<20 {
      let question = try XCTUnwrap(questionGenerator.makeQuestion(mode: .fillInBlank))
      XCTAssertTrue(question.kanaChoices.contains("ツ"), "シ の問題には ツ を混ぜる必要があります")
      XCTAssertEqual(Set(question.kanaChoices).count, 4)
    }
    XCTAssertEqual(Gojuon.similarCharacters(to: "ア"), [])
  }

  func testFillInBlankReturnsNilWhenNoPokemonHasKana() {
    let pokemons = (1...4).map { id in
      Pokemon(id: id, japaneseName: "♀♂ー", spriteURL: URL(string: "https://example.com/\(id).png")!)
    }
    var questionGenerator = QuizQuestionGenerator(
      pokemons: pokemons,
      caughtPokemonIDs: [],
      generator: SeededGenerator(seed: 7)
    )

    XCTAssertNil(questionGenerator.makeQuestion(mode: .fillInBlank))
    XCTAssertNotNil(questionGenerator.makeQuestion(mode: .nameChoice))
  }

  func testAnswerPrefersNotCaughtPokemonButAlsoReviewsCaughtOnes() {
    let pokemons = (1...10).map(makePokemon(id:))
    let caughtPokemonIDs: Set<Int> = [1, 2, 3, 4, 5]
    var questionGenerator = QuizQuestionGenerator(
      pokemons: pokemons,
      caughtPokemonIDs: caughtPokemonIDs,
      generator: SeededGenerator(seed: 20_260_829)
    )
    var notCaughtCount = 0
    var caughtCount = 0

    for _ in 0..<400 {
      guard let question = questionGenerator.makeQuestion(mode: .nameChoice) else {
        XCTFail("10 匹あれば出題できる必要があります")
        return
      }

      if caughtPokemonIDs.contains(question.answer.id) {
        caughtCount += 1
      } else {
        notCaughtCount += 1
      }
    }

    XCTAssertGreaterThan(notCaughtCount, 200)
    XCTAssertGreaterThan(caughtCount, 0)
  }

  func testAnswerComesFromCaughtPokemonWhenNothingIsLeft() {
    let pokemons = (1...10).map(makePokemon(id:))
    var questionGenerator = QuizQuestionGenerator(
      pokemons: pokemons,
      caughtPokemonIDs: Set(pokemons.map(\.id)),
      generator: SeededGenerator(seed: 31)
    )

    for _ in 0..<50 {
      XCTAssertNotNil(questionGenerator.makeQuestion(mode: .nameChoice))
    }
  }

  func testMakeQuestionReturnsNilWhenPokemonsAreFewerThanChoices() {
    for count in 0...3 {
      var questionGenerator = QuizQuestionGenerator(
        pokemons: (0..<count).map { makePokemon(id: $0 + 1) },
        caughtPokemonIDs: [],
        generator: SeededGenerator(seed: 5)
      )

      for mode in QuizMode.allCases {
        XCTAssertNil(questionGenerator.makeQuestion(mode: mode), "\(count) 匹では出題できない必要があります")
      }
    }
  }

  @MainActor
  func testQuizModelSavesProgressOnCorrectAnswerAndKeepsQuestionOnWrongAnswer() async throws {
    let context = ModelContext(try makeContainer())
    let store = LearningProgressStore(modelContext: context)
    let model = makeModel(context: context, store: store)

    await model.load()

    XCTAssertEqual(model.state, .loaded)
    let question = try XCTUnwrap(model.question)
    XCTAssertEqual(question.mode, .nameChoice)

    let wrongChoice = try XCTUnwrap(question.pokemonChoices.first { $0.id != question.answer.id })
    model.answer(pokemon: wrongChoice)

    XCTAssertNil(model.result)
    XCTAssertFalse(model.answered)
    XCTAssertEqual(model.wrongChoiceID, QuizModel.choiceID(pokemon: wrongChoice))
    XCTAssertEqual(model.question, question)

    model.answer(pokemon: question.answer)

    let result = try XCTUnwrap(model.result)
    XCTAssertTrue(result.isNewCatch)
    XCTAssertNil(model.wrongChoiceID)
    XCTAssertEqual(try store.caughtPokemonIDs(), [question.answer.id])
    XCTAssertEqual(
      try store.readCharacters(),
      Gojuon.readableCharacters(in: question.answer.japaneseName)
    )

    model.advance()

    XCTAssertNil(model.result)
    XCTAssertFalse(model.answered)
    XCTAssertEqual(model.mode, .fillInBlank)
    XCTAssertEqual(model.question?.mode, .fillInBlank)
  }

  @MainActor
  func testQuizModelReportsAlreadyCaughtPokemonAsNotNewCatch() async throws {
    let context = ModelContext(try makeContainer())
    let store = LearningProgressStore(modelContext: context)
    for id in 1...6 {
      try store.markPokemonCaught(id: id)
    }
    let model = makeModel(context: context, store: store)

    await model.load()
    let question = try XCTUnwrap(model.question)
    model.answer(pokemon: question.answer)

    XCTAssertEqual(model.result?.isNewCatch, false)
  }

  @MainActor
  func testQuizModelFailsWhenMetadataCannotBeLoaded() async throws {
    let context = ModelContext(try makeContainer())
    let model = QuizModel(
      repository: PokemonRepository(
        modelContext: context,
        dataSource: QuizPokemonDataSourceStub(pokemonByID: [:], failingIDs: [1]),
        pokemonIDs: [1]
      ),
      learningProgressStore: LearningProgressStore(modelContext: context),
      imageCache: nil
    )

    await model.load()

    XCTAssertEqual(model.state, .failed)
    XCTAssertNil(model.question)
  }

  /// 子どもが読めるように、画面に出す文言はかな・数字・約物だけにする。
  func testQuizTextUsesOnlyReadableCharacters() {
    for text in QuizText.all {
      XCTAssertTrue(text.isQuizReadable, "\(text) に かな 以外の文字が含まれている")
    }
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
  private func makeModel(context: ModelContext, store: LearningProgressStore) -> QuizModel {
    let pokemons = (1...6).map(makePokemon(id:))
    return QuizModel(
      repository: PokemonRepository(
        modelContext: context,
        dataSource: QuizPokemonDataSourceStub(
          pokemonByID: Dictionary(uniqueKeysWithValues: pokemons.map { ($0.id, $0) })
        ),
        pokemonIDs: pokemons.map(\.id)
      ),
      learningProgressStore: store,
      imageCache: nil
    )
  }
}

/// テストで乱数を固定するための、シードから結果が決まる乱数生成器 (SplitMix64)。
private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// PokeAPI の代わりに架空のメタデータを返すテスト用データソース。
///
/// `PokemonDataTests` の同種のスタブは `private` で他ファイルから使えないため、ここで用意する。
private actor QuizPokemonDataSourceStub: PokemonDataSource {
  private let pokemonByID: [Int: Pokemon]
  private let failingIDs: Set<Int>

  init(pokemonByID: [Int: Pokemon], failingIDs: Set<Int> = []) {
    self.pokemonByID = pokemonByID
    self.failingIDs = failingIDs
  }

  func fetchPokemon(id: Int) async throws -> Pokemon {
    if failingIDs.contains(id) {
      throw QuizPokemonDataSourceStubError.requestedFailure(id)
    }
    return try XCTUnwrap(pokemonByID[id])
  }
}

private enum QuizPokemonDataSourceStubError: Error, Equatable {
  case requestedFailure(Int)
}

/// 実在のポケモン名を使わないための架空の名前 (`.claude/rules/pokemon-assets-no-commit.md`)。
private let fakePokemonNames = [
  "テストモン", "サンプルン", "ダミーゴン", "モックター",
  "カリモン", "ニセモン", "ハリボテン", "ヨソイモン",
  "ミホンリュウ", "タメシガキ", "ウツシミン", "ケンサモン",
]

private func makePokemon(id: Int) -> Pokemon {
  Pokemon(
    id: id,
    japaneseName: fakePokemonNames[(id - 1) % fakePokemonNames.count],
    spriteURL: URL(string: "https://example.com/\(id).png")!
  )
}

extension String {
  /// ひらがな・カタカナ (長音符・中黒を含む)・半角スペース・数字・全角の ！ ？ だけで構成されているか。
  fileprivate var isQuizReadable: Bool {
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
