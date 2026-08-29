import Foundation
import Observation
import SwiftData

/// なまえ づくり画面がポケモンのデータを読み込めているかを表す。
enum NameBuilderLoadingState: Equatable {
  case loading
  case loaded
  case failed
}

/// なまえ づくり画面の状態を持ち、出題の組み立てと判定、ゲット状況・読めた文字の保存を行う。
@MainActor
@Observable
final class NameBuilderModel {
  private(set) var state: NameBuilderLoadingState = .loading
  private(set) var pokemon: Pokemon?
  private(set) var game: NameBuilderGame?
  /// 正解した時に見せるゲット演出の内容。クイズと同じ内容を見せるため型を共有する。
  private(set) var result: QuizResult?
  /// 保存できなかった「読めた文字」。次の正解でまた出会った時に記録し直すため、握りつぶさず残す。
  private(set) var unsavedReadCharacters: Set<Character> = []
  /// 誤った並びを戻すまでの間か。この間は盤面の操作を受け付けない。
  ///
  /// 戻す前に並べ直せると、古い判定結果が新しい並びへ適用されてしまうため。
  private(set) var rollingBack = false

  let imageCache: PokemonImageCache?

  private let repository: PokemonRepository
  private let learningProgressStore: LearningProgressStore
  private var pokemons: [Pokemon] = []
  private var caughtPokemonIDs: Set<Int> = []
  private var generator: AnyRandomNumberGenerator

  init(
    repository: PokemonRepository,
    learningProgressStore: LearningProgressStore,
    imageCache: PokemonImageCache?,
    generator: some RandomNumberGenerator = SystemRandomNumberGenerator()
  ) {
    self.repository = repository
    self.learningProgressStore = learningProgressStore
    self.imageCache = imageCache
    self.generator = AnyRandomNumberGenerator(generator)
  }

  convenience init(modelContext: ModelContext) {
    self.init(
      repository: PokemonRepository(modelContext: modelContext),
      learningProgressStore: LearningProgressStore(modelContext: modelContext),
      imageCache: try? PokemonImageCache()
    )
  }

  func load() async {
    state = .loading
    result = nil
    rollingBack = false
    do {
      caughtPokemonIDs = try learningProgressStore.caughtPokemonIDs()
      pokemons = try await repository.loadFirstGeneration()
    } catch {
      // 画面を離れた時の取り消しは読み込みの失敗ではないため、「よみこめなかったよ」を出さない。
      // 取り消された時は画面ごと無くなるので、読み込み中のまま残して構わない。
      if !(error is CancellationError), !Task.isCancelled {
        state = .failed
      }
      return
    }

    guard startGame() else {
      state = .failed
      return
    }
    state = .loaded
  }

  func retryLoad() async {
    await load()
  }

  /// タイルをタップして 1 文字置く。全マスが埋まった時だけ判定結果を返す。
  ///
  /// 正解ならこの時点でゲット状況と読めた文字を保存し、`result` を更新する。
  func place(tile: NameBuilderGame.Tile) -> NameBuilderGame.Judgement? {
    guard var game, acceptsInput else {
      return nil
    }

    game.place(tile: tile)
    self.game = game

    guard let judgement = game.judgement() else {
      return nil
    }
    switch judgement {
    case .correct:
      if let pokemon {
        accept(pokemon: pokemon)
      }
    case .rollback:
      rollingBack = true
    }
    return judgement
  }

  /// 埋めたマスをタップして、その位置から後ろをまとめて取り消す。
  func removePlaced(index: Int) {
    guard acceptsInput else {
      return
    }
    game?.removePlaced(index: index)
  }

  /// 「1つ もどす」で直前の 1 文字を取り消す。
  func undo() {
    guard acceptsInput else {
      return
    }
    game?.undo()
  }

  /// 間違えた並びを、先頭から合っている位置まで戻して操作を再開する。
  func rollback(keepCount: Int) {
    game?.rollback(keepCount: keepCount)
    rollingBack = false
  }

  /// 盤面のタップを受け付ける状態か。ゲット演出中と、誤った並びを戻すまでの間は受け付けない。
  var acceptsInput: Bool {
    result == nil && !rollingBack
  }

  /// 次のポケモンの出題へ進む。最後まで行ったら先頭へ戻る。
  func advance() {
    // 並べた文字と名前の読み上げがキューに残っていると、次のポケモンの盤面で鳴り続けるため止める。
    SpeechSynthesizer.shared.stop()
    result = nil
    rollingBack = false
    if let latest = try? learningProgressStore.caughtPokemonIDs() {
      caughtPokemonIDs = latest
    }
    guard let pokemon, let currentIndex = pokemons.firstIndex(where: { $0.id == pokemon.id }) else {
      _ = startGame()
      return
    }

    _ = startGame(index: (currentIndex + 1) % pokemons.count)
  }

  /// 指定した位置のポケモンで出題を組み立てる。組み立てられたら true を返す。
  @discardableResult
  private func startGame(index: Int = 0) -> Bool {
    guard pokemons.indices.contains(index) else {
      return false
    }

    let pokemon = pokemons[index]
    let answer = Array(pokemon.japaneseName)
    self.pokemon = pokemon
    game = NameBuilderGame(
      answer: answer,
      tiles: NameBuilderTileMaker.tiles(answer: answer, generator: &generator)
    )
    return true
  }

  private func accept(pokemon: Pokemon) {
    let notCaughtYet = !caughtPokemonIDs.contains(pokemon.id)
    // 保存に失敗しても遊びは続けられるため画面は止めないが、保存できていないものを
    // ゲット済みとして扱わない (再起動で消える進捗を「とうろく したよ」と見せない)。
    var saved = false
    do {
      try learningProgressStore.markPokemonCaught(id: pokemon.id)
      saved = true
      caughtPokemonIDs.insert(pokemon.id)
    } catch {
      // 保存できなかったゲット情報を未保存のまま残すと、後続の markRead の保存に
      // 巻き込まれて永続化され、画面の表示 (とうろく していない) と食い違うため捨てる。
      learningProgressStore.discardUnsavedChanges()
      saved = false
    }
    for character in Gojuon.readableCharacters(in: pokemon.japaneseName) {
      do {
        try learningProgressStore.markRead(character: character)
      } catch {
        // 保存できなかった文字を未保存のまま残すと、次の保存に巻き込まれて永続化されるため捨てる。
        // 読めた文字は同じ文字に別のポケモンで出会った時に記録し直せるので、遊びは止めない。
        learningProgressStore.discardUnsavedChanges()
        unsavedReadCharacters.insert(character)
      }
    }

    result = QuizResult(pokemon: pokemon, isNewCatch: notCaughtYet && saved)
  }
}
