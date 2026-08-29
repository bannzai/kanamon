import CoreGraphics
import Foundation
import Observation
import SwiftData

/// かきれんしゅう画面に出す案内文。子どもが読めるようにひらがな・カタカナで書く。
enum KakiRenshuMessage {
  static let loading = "よみこみ ちゅう…"
  static let traceFromFirstStroke = "きいろい ① から やじるし の むき に なぞろう"
  static let traceAgain = "もう いちど  やじるし に そって ゆっくり なぞろう"
  static let characterWritten = "かけたね！"
  static let strokeDataUnavailable = "この もじ の かきじゅん は よういして いません"
  static let nameWritten = "ぜんぶ かけたね！"
  static let loadFailed = "つうしん が できません  もう いちど ためして ね"

  static func traceStroke(number: Int) -> String {
    "\(number) かくめ  やじるし の むき に なぞろう"
  }
}

/// かきれんしゅう画面の進行状態を持ち、書き順データの取得となぞり判定・進捗保存をまとめる。
///
/// 名前の文字を 1 文字ずつ、画を 1 画ずつ順番になぞらせ、全文字書けたらそのポケモンをゲット扱いにする。
@MainActor
@Observable
final class KakiRenshuModel {
  /// 画面が今どの段階にあるか。
  enum Phase: Equatable {
    case loading
    case tracing
    case failure
  }

  private(set) var phase: Phase = .loading
  private(set) var pokemon: [Pokemon] = []
  private(set) var pokemonIndex = 0
  /// 今なぞっている文字の、名前の中での位置。
  private(set) var characterIndex = 0
  /// 今なぞっている文字の画を、書き順の順に並べたもの。
  private(set) var strokes: [StrokePath] = []
  /// 今なぞっている画の番号 (0 始まり)。書き終えた画の数でもある。
  private(set) var strokeIndex = 0
  /// これまでに書けた文字を正規化して持つ (ピ→ヒ、ャ→ヤ)。
  private(set) var writtenCharacters: Set<Character> = []
  private(set) var message = KakiRenshuMessage.loading
  /// なぞりに失敗した回数。面を揺らすアニメーションのきっかけに使う。
  private(set) var failureCount = 0
  /// ゲット演出で見せるポケモン。演出中でなければ nil にする。
  private(set) var caughtPokemon: Pokemon?

  /// スプライト画像の取得に使うキャッシュ。画面側の `PokemonSpriteView` へ渡す。
  let imageCache: PokemonImageCache?

  private var progressStore: LearningProgressStore?
  private let strokeCache: KanjiVGCache?
  /// 一度読んだ文字の画を保持し、同じ文字で再解析しないようにする。
  private var parsedStrokes: [Character: [StrokePath]] = [:]
  private var strokeLoadingTask: Task<Void, Never>?
  /// 1 文字書けてから次の文字へ移るまでの待ち。「かけたね！」を読ませるために置く。
  private var advanceTask: Task<Void, Never>?

  /// キャッシュディレクトリを作れない端末でも画面は開けるようにするため、生成に失敗したら nil を既定にする。
  init(
    strokeCache: KanjiVGCache? = try? KanjiVGCache(),
    imageCache: PokemonImageCache? = try? PokemonImageCache()
  ) {
    self.strokeCache = strokeCache
    self.imageCache = imageCache
  }

  /// 今表示しているポケモン。まだ読み込めていなければ nil。
  var currentPokemon: Pokemon? {
    guard pokemon.indices.contains(pokemonIndex) else {
      return nil
    }

    return pokemon[pokemonIndex]
  }

  /// 今の名前を 1 文字ずつに分けたもの。
  var characters: [Character] {
    guard let currentPokemon else {
      return []
    }

    return Array(currentPokemon.japaneseName)
  }

  /// その文字が既に書けているか。濁点・小書き文字は元の文字に合わせて判定する。
  func isWritten(_ character: Character) -> Bool {
    writtenCharacters.contains(KatakanaCharacterNormalizer.baseCharacter(from: character))
  }

  func load(modelContext: ModelContext) async {
    guard pokemon.isEmpty else {
      return
    }

    phase = .loading
    message = KakiRenshuMessage.loading
    let store = LearningProgressStore(modelContext: modelContext)
    progressStore = store
    writtenCharacters = (try? store.writtenCharacters()) ?? []

    do {
      let loaded = try await PokemonRepository(modelContext: modelContext).loadFirstGeneration()
      guard !loaded.isEmpty else {
        phase = .failure
        message = KakiRenshuMessage.loadFailed
        return
      }

      pokemon = loaded
      phase = .tracing
      loadStrokes(startingAt: 0)
    } catch {
      phase = .failure
      message = KakiRenshuMessage.loadFailed
    }
  }

  func showPokemon(offsetBy offset: Int) {
    guard !pokemon.isEmpty else {
      return
    }

    cancelPendingWork()
    caughtPokemon = nil
    pokemonIndex = ((pokemonIndex + offset) % pokemon.count + pokemon.count) % pokemon.count
    characterIndex = 0
    loadStrokes(startingAt: 0)
  }

  func selectCharacter(at index: Int) {
    guard characters.indices.contains(index) else {
      return
    }

    cancelPendingWork()
    characterIndex = index
    loadStrokes(startingAt: index)
  }

  /// なぞり終えた軌跡 (109 座標系) を判定し、成功なら次の画・次の文字へ進める。
  func finishTrace(_ trace: [CGPoint]) {
    guard caughtPokemon == nil, strokes.indices.contains(strokeIndex) else {
      return
    }
    guard StrokeTraceJudge.isTraced(trace: trace, stroke: strokes[strokeIndex]) else {
      failureCount += 1
      message = KakiRenshuMessage.traceAgain
      return
    }

    strokeIndex += 1
    guard strokeIndex >= strokes.count else {
      message = KakiRenshuMessage.traceStroke(number: strokeIndex + 1)
      return
    }

    guard characters.indices.contains(characterIndex) else {
      return
    }
    let character = characters[characterIndex]
    markWritten(character)
    message = KakiRenshuMessage.characterWritten
    SpeechSynthesizer.shared.speak(String(character))

    let nextCharacterIndex = characterIndex + 1
    advanceTask = Task {
      try? await Task.sleep(for: .milliseconds(800))
      guard !Task.isCancelled else {
        return
      }

      if nextCharacterIndex < characters.count {
        loadStrokes(startingAt: nextCharacterIndex)
      } else {
        finishName()
      }
    }
  }

  /// ゲット演出を閉じて、次のポケモンの名前へ進む。
  func dismissCaughtPokemon() {
    caughtPokemon = nil
    showPokemon(offsetBy: 1)
  }

  func speakCurrentCharacter() {
    guard characters.indices.contains(characterIndex) else {
      return
    }

    SpeechSynthesizer.shared.speak(String(characters[characterIndex]))
  }

  private func markWritten(_ character: Character) {
    try? progressStore?.markWritten(character: character)
    writtenCharacters.insert(KatakanaCharacterNormalizer.baseCharacter(from: character))
  }

  private func finishName() {
    guard let currentPokemon else {
      return
    }

    try? progressStore?.markPokemonCaught(id: currentPokemon.id)
    message = KakiRenshuMessage.nameWritten
    caughtPokemon = currentPokemon
    SpeechSynthesizer.shared.speak(currentPokemon.japaneseName)
  }

  /// `startIndex` 以降で書き順データのある文字を探し、その文字のなぞりを始める。
  ///
  /// ニドラン♀ の「♀」のように KanjiVG に無い文字は飛ばす。名前を書き終えられなくしないための扱い。
  private func loadStrokes(startingAt startIndex: Int) {
    strokeLoadingTask?.cancel()
    strokes = []
    strokeIndex = 0
    message = KakiRenshuMessage.loading

    let characters = self.characters
    strokeLoadingTask = Task {
      var index = startIndex
      while index < characters.count {
        let loadedStrokes = await strokeData(for: characters[index])
        guard !Task.isCancelled else {
          return
        }

        if let loadedStrokes, !loadedStrokes.isEmpty {
          characterIndex = index
          strokes = loadedStrokes
          strokeIndex = 0
          message = KakiRenshuMessage.traceFromFirstStroke
          return
        }
        index += 1
      }

      guard !Task.isCancelled else {
        return
      }

      if startIndex > 0 {
        // ここまでの文字は書けているため、名前を書き終えた扱いにする。
        characterIndex = max(0, characters.count - 1)
        finishName()
      } else {
        message = KakiRenshuMessage.strokeDataUnavailable
      }
    }
  }

  private func strokeData(for character: Character) async -> [StrokePath]? {
    if let cached = parsedStrokes[character] {
      return cached
    }
    guard let strokeCache else {
      return nil
    }
    guard let data = try? await strokeCache.strokeData(for: character),
      let parsed = try? KanjiVGStrokeParser.strokes(from: data)
    else {
      return nil
    }

    parsedStrokes[character] = parsed
    return parsed
  }

  private func cancelPendingWork() {
    advanceTask?.cancel()
    advanceTask = nil
    strokeLoadingTask?.cancel()
    strokeLoadingTask = nil
  }
}
