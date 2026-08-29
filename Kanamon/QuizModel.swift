import Foundation
import Observation
import SwiftData

/// クイズ画面がポケモンのデータを読み込めているかを表す。
enum QuizLoadingState: Equatable {
  case loading
  case loaded
  case failed
}

/// 正解したときに見せるゲット演出の内容を表す。
struct QuizResult: Equatable {
  let pokemon: Pokemon
  /// この正解ではじめてゲットしたか。すでにゲット済みだった場合は false。
  let isNewCatch: Bool
}

/// クイズ画面の状態を持ち、出題と採点、ゲット状況・読めた文字の保存を行う。
@MainActor
@Observable
final class QuizModel {
  private(set) var state: QuizLoadingState = .loading
  private(set) var question: QuizQuestion?
  private(set) var mode: QuizMode = .nameChoice
  private(set) var answered = false
  /// 直前に選んだ不正解の選択肢。画面はこの選択肢だけを揺らす。
  private(set) var wrongChoiceID: String?
  private(set) var result: QuizResult?

  let imageCache: PokemonImageCache?

  private let repository: PokemonRepository
  private let caughtPokemonStore: CaughtPokemonStore
  private let readKanaStore: ReadKanaStore
  private var pokemons: [Pokemon] = []
  private var caughtPokemonIDs: Set<Int> = []

  init(
    repository: PokemonRepository,
    caughtPokemonStore: CaughtPokemonStore,
    readKanaStore: ReadKanaStore,
    imageCache: PokemonImageCache?
  ) {
    self.repository = repository
    self.caughtPokemonStore = caughtPokemonStore
    self.readKanaStore = readKanaStore
    self.imageCache = imageCache
  }

  convenience init(modelContext: ModelContext) {
    self.init(
      repository: PokemonRepository(modelContext: modelContext),
      caughtPokemonStore: CaughtPokemonStore(modelContext: modelContext),
      readKanaStore: ReadKanaStore(modelContext: modelContext),
      imageCache: try? PokemonImageCache()
    )
  }

  /// 選択肢を画面側で見分けるための識別子。ポケモンと文字で前置きを変え、取り違えを防ぐ。
  static func choiceID(pokemon: Pokemon) -> String {
    "pokemon-\(pokemon.id)"
  }

  static func choiceID(kana: Character) -> String {
    "kana-\(kana)"
  }

  func load() async {
    state = .loading
    do {
      caughtPokemonIDs = try caughtPokemonStore.caughtPokemonIDs()
      pokemons = try await repository.loadFirstGeneration()
    } catch {
      state = .failed
      return
    }

    guard let question = makeQuestion() else {
      state = .failed
      return
    }

    self.question = question
    state = .loaded
  }

  func retryLoad() async {
    await load()
  }

  func answer(pokemon: Pokemon) {
    guard let question, !answered else {
      return
    }

    if pokemon.id == question.answer.id {
      accept(pokemon: question.answer)
    } else {
      wrongChoiceID = Self.choiceID(pokemon: pokemon)
    }
  }

  func answer(kana: Character) {
    guard let question, let blankIndex = question.blankIndex, !answered else {
      return
    }

    let characters = Array(question.answer.japaneseName)
    guard characters.indices.contains(blankIndex) else {
      return
    }

    if kana == characters[blankIndex] {
      accept(pokemon: question.answer)
    } else {
      wrongChoiceID = Self.choiceID(kana: kana)
    }
  }

  /// 次の問題へ進む。正解していなくても呼べる (画面のスワイプで飛ばせる)。
  func advance() {
    result = nil
    answered = false
    wrongChoiceID = nil
    mode = mode.next

    if let latest = try? caughtPokemonStore.caughtPokemonIDs() {
      caughtPokemonIDs = latest
    }
    if let next = makeQuestion() {
      question = next
    }
  }

  private func accept(pokemon: Pokemon) {
    answered = true
    wrongChoiceID = nil

    let isNewCatch = !caughtPokemonIDs.contains(pokemon.id)
    // 保存に失敗しても出題は続けられるため、クイズを止めずに進める。
    try? caughtPokemonStore.markCaught(pokemonID: pokemon.id)
    try? readKanaStore.markRead(name: pokemon.japaneseName)
    caughtPokemonIDs.insert(pokemon.id)

    result = QuizResult(pokemon: pokemon, isNewCatch: isNewCatch)
  }

  private func makeQuestion() -> QuizQuestion? {
    var questionGenerator = QuizQuestionGenerator(
      pokemons: pokemons,
      caughtPokemonIDs: caughtPokemonIDs
    )
    return questionGenerator.makeQuestion(mode: mode)
  }
}
