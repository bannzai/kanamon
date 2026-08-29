import Foundation
import SwiftData
import XCTest

@testable import Kanamon

@MainActor
final class YomiRenshuTests: XCTestCase {
  func testCharactersPairEachKatakanaWithHiragana() async throws {
    let model = try makeModel(names: ["テストモン"])
    await model.load()

    XCTAssertEqual(model.state, .loaded)
    XCTAssertEqual(model.characters.map(\.katakana), ["テ", "ス", "ト", "モ", "ン"])
    XCTAssertEqual(model.characters.map(\.hiragana), ["て", "す", "と", "も", "ん"])
    XCTAssertEqual(model.characters.map(\.index), [0, 1, 2, 3, 4])
  }

  /// 小書き文字・長音符・カナ以外の記号が名前に混ざっても、そのままセルに並べる。
  func testCharactersKeepSmallKanaLongVowelAndSymbol() async throws {
    let model = try makeModel(names: ["キョーダイモン♀"])
    await model.load()

    XCTAssertEqual(model.characters.map(\.katakana), ["キ", "ョ", "ー", "ダ", "イ", "モ", "ン", "♀"])
    XCTAssertEqual(model.characters.map(\.hiragana), ["き", "ょ", "ー", "だ", "い", "も", "ん", "♀"])
  }

  func testSimilarKatakanaCoversEightPairsAndTipsStartWithTappedCharacter() throws {
    XCTAssertEqual(SimilarKatakana.allCharacters.count, 16)

    for character in SimilarKatakana.allCharacters {
      XCTAssertTrue(SimilarKatakana.isSimilar(character: character))
      let tip = try XCTUnwrap(SimilarKatakana.tip(character: character))
      XCTAssertTrue(tip.hasPrefix("\(character) は"), "\(character) の tip が \(tip) で始まっている")
      XCTAssertEqual(tip.split(separator: "\n").count, 2, "\(character) の tip が 2 行になっていない")
    }

    XCTAssertEqual(
      SimilarKatakana.tip(character: "ツ"),
      "ツ は てんてん が たてむき\nシ は てんてん が よこむき"
    )
    for character in ["ワ", "ヲ", "ラ"] as [Character] {
      XCTAssertFalse(SimilarKatakana.isSimilar(character: character))
      XCTAssertNil(SimilarKatakana.tip(character: character))
    }
  }

  func testPlayAllSpeaksEachCharacterThenWholeNameAndRecordsProgress() async throws {
    let modelContext = try makeModelContext(names: ["ガードモン"])
    let speechSynthesizer = SpeechSynthesizerStub()
    let model = makeModel(
      modelContext: modelContext,
      pokemonCount: 1,
      speechSynthesizer: speechSynthesizer
    )
    await model.load()
    await model.playAll()

    XCTAssertEqual(speechSynthesizer.spokenTexts, ["ガ", "ー", "ド", "モ", "ン", "ガードモン"])
    XCTAssertFalse(model.isPlaying)
    XCTAssertTrue(model.highlightedIndices.isEmpty)
    XCTAssertEqual(
      try LearningProgressStore(modelContext: modelContext).readCharacters(),
      ["カ", "ト", "モ", "ン"]
    )
  }

  func testStopEndsPlaybackAndAsksSynthesizerToStop() async throws {
    let speechSynthesizer = SpeechSynthesizerStub()
    let model = try makeModel(names: ["テストモン"], speechSynthesizer: speechSynthesizer)
    await model.load()
    await model.playAll()

    model.stop()

    XCTAssertFalse(model.isPlaying)
    XCTAssertTrue(model.highlightedIndices.isEmpty)
    XCTAssertGreaterThanOrEqual(speechSynthesizer.stopCount, 1)
  }

  func testTapSpeaksTappedCharacterAndShowsTipForSimilarCharacter() async throws {
    let modelContext = try makeModelContext(names: ["シラモン"])
    let speechSynthesizer = SpeechSynthesizerStub()
    let model = makeModel(
      modelContext: modelContext,
      pokemonCount: 1,
      speechSynthesizer: speechSynthesizer
    )
    await model.load()

    await model.tap(index: 0)
    XCTAssertEqual(speechSynthesizer.spokenTexts, ["シ"])
    XCTAssertEqual(model.tipText, "シ は てんてん が よこむき\nツ は てんてん が たてむき")
    XCTAssertEqual(try LearningProgressStore(modelContext: modelContext).readCharacters(), ["シ"])

    await model.tap(index: 1)
    XCTAssertNil(model.tipText)
  }

  /// 記号を読み上げても五十音の進捗には数えず、クラッシュもしない。
  func testTapOnSymbolDoesNotRecordProgress() async throws {
    let modelContext = try makeModelContext(names: ["テストモン♀"])
    let model = makeModel(
      modelContext: modelContext,
      pokemonCount: 1,
      speechSynthesizer: SpeechSynthesizerStub()
    )
    await model.load()

    await model.tap(index: 5)

    XCTAssertTrue(try LearningProgressStore(modelContext: modelContext).readCharacters().isEmpty)
  }

  func testNextAndPreviousLoopAroundEnds() async throws {
    let model = try makeModel(names: ["テストモン", "サンプルン", "ミスモン"])
    await model.load()

    XCTAssertEqual(model.currentIndex, 0)
    model.previous()
    XCTAssertEqual(model.currentIndex, 2)
    model.next()
    XCTAssertEqual(model.currentIndex, 0)
    model.next()
    model.next()
    model.next()
    XCTAssertEqual(model.currentIndex, 0)
  }

  func testMovingToAnotherPokemonHidesTip() async throws {
    let model = try makeModel(names: ["シラモン", "サンプルン"])
    await model.load()

    await model.tap(index: 0)
    XCTAssertNotNil(model.tipText)
    model.next()

    XCTAssertNil(model.tipText)
  }

  func testInitialPokemonIDOpensThatPokemon() async throws {
    let modelContext = try makeModelContext(names: ["テストモン", "サンプルン", "ミスモン"])
    let model = YomiRenshuModel(
      modelContext: modelContext,
      initialPokemonID: 3,
      repository: PokemonRepository(
        modelContext: modelContext,
        dataSource: UnavailablePokemonDataSource(),
        pokemonIDs: [1, 2, 3]
      ),
      speechSynthesizer: SpeechSynthesizerStub(),
      sleep: { _ in }
    )
    await model.load()

    XCTAssertEqual(model.currentIndex, 2)
    XCTAssertEqual(model.currentPokemon?.japaneseName, "ミスモン")
  }

  /// 同じ文字を続けてタップした時、先のタップの後始末で後のタップのハイライトを消さない。
  func testTapKeepsLatestHighlightWhenEarlierTapFinishesLater() async throws {
    let sleepGate = SleepGate()
    let modelContext = try makeModelContext(names: ["テストモン"])
    let model = YomiRenshuModel(
      modelContext: modelContext,
      repository: PokemonRepository(
        modelContext: modelContext,
        dataSource: UnavailablePokemonDataSource(),
        pokemonIDs: [1]
      ),
      speechSynthesizer: SpeechSynthesizerStub(),
      sleep: { _ in await sleepGate.wait() }
    )
    await model.load()

    let earlierTap = Task { await model.tap(index: 0) }
    await waitUntil(message: "1 回目のタップがハイライトの待ちに入らなかった") { sleepGate.waitingCount == 1 }
    let laterTap = Task { await model.tap(index: 0) }
    await waitUntil(message: "2 回目のタップがハイライトの待ちに入らなかった") { sleepGate.waitingCount == 2 }

    sleepGate.releaseEarliest()
    await earlierTap.value

    XCTAssertEqual(model.highlightedIndices, [0])

    sleepGate.releaseEarliest()
    await laterTap.value
    XCTAssertTrue(model.highlightedIndices.isEmpty)
  }

  /// 画面に出す固定文言と見分け方は、子どもが読めるひらがな・カタカナと空白だけにする。
  func testFixedTextsUseOnlyKanaAndSpacing() throws {
    for text in YomiRenshuText.all {
      XCTAssertTrue(text.isKanaWithSpacing, "\(text) にひらがな・カタカナ以外の文字が含まれている")
    }

    for character in SimilarKatakana.allCharacters {
      let tip = try XCTUnwrap(SimilarKatakana.tip(character: character))
      XCTAssertTrue(tip.isKanaWithSpacing, "\(character) の tip にひらがな・カタカナ以外の文字が含まれている")
    }
  }

  func testViewCanBeInstantiated() {
    XCTAssertNotNil(YomiRenshuView().body)
  }

  /// 条件が満たされるまで、他の Task に順番を譲りながら待つ。
  ///
  /// - Parameter message: 待っても条件が満たされなかった時に出す説明
  private func waitUntil(message: String, condition: () -> Bool) async {
    // 譲る回数の上限。タップが待ちに入るまでに必要な回数より十分多くし、
    // 条件が満たされないまま無限に待たずにテストを失敗させる
    for _ in 0..<1000 {
      if condition() {
        return
      }

      await Task.yield()
    }

    XCTFail(message)
  }

  private func makeModel(
    names: [String],
    speechSynthesizer: any SpeechSynthesizing = SpeechSynthesizerStub()
  ) throws -> YomiRenshuModel {
    let modelContext = try makeModelContext(names: names)
    return makeModel(
      modelContext: modelContext,
      pokemonCount: names.count,
      speechSynthesizer: speechSynthesizer
    )
  }

  private func makeModel(
    modelContext: ModelContext,
    pokemonCount: Int,
    speechSynthesizer: any SpeechSynthesizing
  ) -> YomiRenshuModel {
    YomiRenshuModel(
      modelContext: modelContext,
      repository: PokemonRepository(
        modelContext: modelContext,
        dataSource: UnavailablePokemonDataSource(),
        pokemonIDs: Array(1...pokemonCount)
      ),
      speechSynthesizer: speechSynthesizer,
      // テストが実時間を待たないよう、間を置く処理を何もしない実装に差し替える
      sleep: { _ in }
    )
  }

  /// 架空の名前だけをキャッシュに入れたメモリ内の ModelContext を用意する。
  private func makeModelContext(names: [String]) throws -> ModelContext {
    let container = try ModelContainer(
      for: PokemonCacheEntry.self,
      CaughtPokemonEntry.self,
      CharacterProgressEntry.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let modelContext = ModelContext(container)

    for (offset, name) in names.enumerated() {
      modelContext.insert(
        PokemonCacheEntry(
          pokemon: Pokemon(
            id: offset + 1,
            japaneseName: name,
            spriteURL: URL(string: "https://example.com/\(offset + 1).png")!
          )
        )
      )
    }
    try modelContext.save()

    return modelContext
  }
}

/// AVSpeechSynthesizer の代わりに、渡された文字列を記録するだけのテスト用読み上げ。
private final class SpeechSynthesizerStub: SpeechSynthesizing {
  private(set) var spokenTexts: [String] = []
  private(set) var stopCount = 0

  func speak(text: String, rate: Float) async {
    spokenTexts.append(text)
  }

  func stop() {
    stopCount += 1
  }
}

/// 間を置く処理の代わりに使い、待っている Task をテストの好きな順番で先へ進めるスタブ。
///
/// 待ちは別の Task から積まれるため、溜めた continuation の受け渡しを lock で直列化する。
private final class SleepGate: @unchecked Sendable {
  private let lock = NSLock()
  private var continuations: [CheckedContinuation<Void, Never>] = []

  /// いま解放を待っている数。
  var waitingCount: Int {
    lock.withLock { continuations.count }
  }

  /// `releaseEarliest()` で解放されるまで返らない。
  func wait() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      lock.withLock { continuations.append(continuation) }
    }
  }

  /// 待ちに入るのが早かったものから 1 つ解放する。待ちが無い時は何も起きない。
  func releaseEarliest() {
    let continuation = lock.withLock { continuations.isEmpty ? nil : continuations.removeFirst() }
    continuation?.resume()
  }
}

/// キャッシュ済みのデータだけで画面が動くことを確かめるため、呼ばれたら失敗するデータソース。
private struct UnavailablePokemonDataSource: PokemonDataSource {
  func fetchPokemon(id: Int) async throws -> Pokemon {
    XCTFail("キャッシュ済みのポケモンだけで動く必要があります")
    throw UnavailablePokemonDataSourceError.requested(id)
  }
}

private enum UnavailablePokemonDataSourceError: Error {
  case requested(Int)
}

extension String {
  /// ひらがな (U+3041-U+309F)・カタカナ (U+30A0-U+30FF) と、半角スペース・改行だけで構成されているか。
  ///
  /// `HomeViewTests` の判定は空白を許さないため、複数語の文言を扱えるようにここで別に定義する。
  fileprivate var isKanaWithSpacing: Bool {
    unicodeScalars.allSatisfy { scalar in
      (0x3041...0x309F).contains(scalar.value)
        || (0x30A0...0x30FF).contains(scalar.value)
        || scalar.value == 0x20
        || scalar.value == 0x0A
    }
  }
}
