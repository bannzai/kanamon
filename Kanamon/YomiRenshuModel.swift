import Foundation
import Observation
import SwiftData

/// よみれんしゅう画面に並べる名前の 1 文字分の表示内容。
struct YomiRenshuCharacter: Identifiable, Equatable {
  /// 名前の先頭からの位置。ハイライト対象の指定にも使う。
  let index: Int
  let katakana: Character
  /// カタカナに対応するひらがな。長音符・記号は変換されずそのまま入る。
  let hiragana: String
  /// 形がにていて読み間違えやすい文字か。
  let isSimilar: Bool

  var id: Int { index }
}

/// よみれんしゅう画面のデータ取得の状態。
enum YomiRenshuState: Equatable {
  case loading
  case loaded
  case failed
}

/// よみれんしゅう画面の表示内容と読み上げの進行を保持する。
///
/// 依存はすべて init で差し替えられるようにし、テストではスタブの読み上げとメモリ内 SwiftData を使う。
@MainActor
@Observable
final class YomiRenshuModel {
  /// 練習の対象にする第 1 世代のポケモン。図鑑番号の順に並ぶ。
  private(set) var pokemons: [Pokemon] = []
  /// いま画面に出しているポケモンの `pokemons` 内の位置。
  private(set) var currentIndex = 0
  private(set) var state: YomiRenshuState = .loading
  /// 黄色く光らせる文字の位置。ぜんぶ よむ の最後は名前全体を光らせる。
  private(set) var highlightedIndices: Set<Int> = []
  /// ぜんぶ よむ の再生中か。
  private(set) var isPlaying = false
  /// にている もじ をタップした時に出す見分け方の 2 行。出さない時は nil。
  private(set) var tipText: String?

  /// モンスターの画像を読み込むキャッシュ。Caches ディレクトリを用意できなかった端末では nil になる。
  let imageCache: PokemonImageCache?

  private let repository: PokemonRepository
  private let learningProgressStore: LearningProgressStore
  private let speechSynthesizer: any SpeechSynthesizing
  private let sleep: @Sendable (Duration) async -> Void
  private let initialPokemonID: Int?
  private var playbackTask: Task<Void, Never>?
  /// タップを受けた順の通し番号。読み終わりを待つ間に次のタップが来たかを見分けるのに使う。
  private var tapGeneration = 0

  /// 1 音をはっきり聞かせるため、`AVSpeechUtterance` の既定 (0.5) より遅くする。
  private static let singleCharacterRate: Float = 0.4
  /// 名前全体は 1 つの語として自然に聞こえるよう、`AVSpeechUtterance` の既定の速さで通して読む。
  private static let wholeNameRate: Float = 0.5
  /// 音が続けて鳴って区切りが分からなくならないよう、次の文字へ移る前に短い間を置く。
  private static let intervalBetweenCharacters = Duration.milliseconds(90)
  /// タップした文字がどれだったか目で追えるように、読み終わりが早くてもこの長さは光らせる。
  private static let tapHighlightDuration = Duration.milliseconds(900)

  /// 依存をすべて省略した時は、画面から使う本番の実装を `modelContext` から組み立てる。
  ///
  /// - Parameters:
  ///   - initialPokemonID: 開始位置のポケモン。ホームからは指定がないため、省略時は先頭から始める
  ///   - sleep: 間を置く処理。省略時は実時間を待ち、テストでは待たない実装に差し替える
  init(
    modelContext: ModelContext,
    initialPokemonID: Int? = nil,
    repository: PokemonRepository? = nil,
    learningProgressStore: LearningProgressStore? = nil,
    speechSynthesizer: (any SpeechSynthesizing)? = nil,
    imageCache: PokemonImageCache? = nil,
    sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
  ) {
    self.initialPokemonID = initialPokemonID
    self.repository = repository ?? PokemonRepository(modelContext: modelContext)
    self.learningProgressStore = learningProgressStore ?? LearningProgressStore(modelContext: modelContext)
    self.speechSynthesizer = speechSynthesizer ?? JapaneseSpeechSynthesizer()
    self.imageCache = imageCache ?? (try? PokemonImageCache())
    self.sleep = sleep
  }

  /// いま画面に出しているポケモン。取得前と取得結果が空の時は nil。
  var currentPokemon: Pokemon? {
    guard pokemons.indices.contains(currentIndex) else {
      return nil
    }

    return pokemons[currentIndex]
  }

  /// いま画面に出しているポケモンの名前を、1 文字ずつのセルに分けたもの。
  var characters: [YomiRenshuCharacter] {
    guard let currentPokemon else {
      return []
    }

    return currentPokemon.japaneseName.enumerated().map { index, katakana in
      YomiRenshuCharacter(
        index: index,
        katakana: katakana,
        hiragana: KatakanaConverter.hiragana(from: String(katakana)),
        isSimilar: SimilarKatakana.isSimilar(character: katakana)
      )
    }
  }

  /// 練習の対象を読み込む。何度呼んでもキャッシュ優先で同じ結果になる。
  func load() async {
    state = .loading
    do {
      let pokemons = try await repository.loadFirstGeneration()
      self.pokemons = pokemons
      // 開始位置の指定がない・指定のポケモンが取れなかった場合は先頭から始める
      currentIndex = pokemons.firstIndex { $0.id == initialPokemonID } ?? 0
      // 1 匹も取れていない時は画面に出せるものが無いため、取得失敗と同じ扱いにして再取得できるようにする
      state = pokemons.isEmpty ? .failed : .loaded
    } catch {
      state = .failed
    }
  }

  /// 先頭の文字から 1 文字ずつ光らせて読み、最後に名前全体を通しで読む。読み終わるまで返らない。
  func playAll() async {
    guard !isPlaying, currentPokemon != nil else {
      return
    }

    isPlaying = true
    tipText = nil
    let playbackTask = Task { await self.playAllCharacters() }
    self.playbackTask = playbackTask
    await playbackTask.value
  }

  /// 再生を中断してハイライトを消す。再生していない時に呼んでも何も起きない。
  func stop() {
    playbackTask?.cancel()
    playbackTask = nil
    speechSynthesizer.stop()
    highlightedIndices = []
    isPlaying = false
  }

  /// タップされた文字だけを光らせて 1 音読む。にている もじ なら見分け方も出す。
  func tap(index: Int) async {
    guard let character = characters.first(where: { $0.index == index }) else {
      return
    }

    stop()
    tapGeneration += 1
    let generation = tapGeneration
    tipText = SimilarKatakana.tip(character: character.katakana)
    highlightedIndices = [index]
    markRead(katakana: character.katakana)

    let highlightTask = Task { await self.sleep(Self.tapHighlightDuration) }
    await speechSynthesizer.speak(text: String(character.katakana), rate: Self.singleCharacterRate)
    await highlightTask.value

    // 待っている間に次のタップや ぜんぶ よむ が始まっていたら、そちらのハイライトを消さない
    if generation == tapGeneration, highlightedIndices == [index] {
      highlightedIndices = []
    }
  }

  /// 次のポケモンへ送る。末尾からは先頭へ戻る。
  func next() {
    move(offset: 1)
  }

  /// 前のポケモンへ戻る。先頭からは末尾へ回る。
  func previous() {
    move(offset: -1)
  }

  private func playAllCharacters() async {
    guard let currentPokemon else {
      return
    }

    let characters = self.characters
    for character in characters {
      if Task.isCancelled {
        return
      }

      highlightedIndices = [character.index]
      markRead(katakana: character.katakana)
      await speechSynthesizer.speak(text: String(character.katakana), rate: Self.singleCharacterRate)
      await sleep(Self.intervalBetweenCharacters)
    }

    if Task.isCancelled {
      return
    }

    highlightedIndices = Set(characters.map(\.index))
    await speechSynthesizer.speak(text: currentPokemon.japaneseName, rate: Self.wholeNameRate)

    // 中断された場合の後始末は stop() が済ませているため、最後まで読めた時だけ戻す
    if !Task.isCancelled {
      highlightedIndices = []
      isPlaying = false
      playbackTask = nil
    }
  }

  private func move(offset: Int) {
    guard !pokemons.isEmpty else {
      return
    }

    stop()
    tipText = nil
    currentIndex = (currentIndex + offset + pokemons.count) % pokemons.count
  }

  private func markRead(katakana: Character) {
    guard Self.isProgressCharacter(character: katakana) else {
      return
    }

    try? learningProgressStore.markRead(character: katakana)
  }

  /// 五十音の進捗に数える文字か。名前に混ざる記号 (♀ ♂ 等) と長音符「ー」は数えない。
  private static func isProgressCharacter(character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first else {
      return false
    }

    // U+30A1 (ァ) から U+30FA (ヺ) がカタカナの文字。U+30FB (・) 以降の記号と長音符はここに含まれない
    return (0x30A1...0x30FA).contains(scalar.value)
  }
}
