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
  static let strokeLoadFailed = "かきじゅん を よみこめません  つうしん を たしかめて もじ を タップ してね"
  static let nameWritten = "ぜんぶ かけたね！"
  static let registerFailed = "とうろく できなかったよ  もう いちど ためして ね"
  static let loadFailed = "つうしん が できません  もう いちど ためして ね"
  static let retry = "もう いちど"

  static func traceStroke(number: Int) -> String {
    "\(number) かくめ  やじるし の むき に なぞろう"
  }
}

/// 名前を書き終えた時にゲット演出へ渡す結果。ずかんへ登録できたかで見せる文言を変える。
struct KakiRenshuResult: Equatable {
  let pokemon: Pokemon
  /// ずかんへの登録を保存できたか。保存に失敗した時は登録できた形で見せない。
  let isRegistered: Bool
}

/// かきれんしゅう画面の進行状態を持ち、書き順データの取得となぞり判定・進捗保存をまとめる。
///
/// 名前の文字を 1 文字ずつ、画を 1 画ずつ順番になぞらせ、名前の全文字を書けたらそのポケモンをゲット扱いにする。
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
  /// ゲット演出で見せる結果。演出中でなければ nil にする。
  private(set) var result: KakiRenshuResult?

  /// スプライト画像の取得に使うキャッシュ。画面側の `PokemonSpriteView` へ渡す。
  let imageCache: PokemonImageCache?

  private var progressStore: LearningProgressStore?
  private let strokeCache: KanjiVGCache?
  /// 一度読んだ文字の画を保持し、同じ文字で再解析しないようにする。
  private var parsedStrokes: [Character: [StrokePath]] = [:]
  /// KanjiVG に書き順データが無いと分かった文字。同じ文字を取り直さないために持つ。
  private var unsupportedCharacters: Set<Character> = []
  /// 今のポケモンの名前の進み具合。ゲットの確定はこれで判定する。
  private var nameProgress = NameWritingProgress(characterCount: 0)
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
      resetNameProgress()
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
    result = nil
    pokemonIndex = ((pokemonIndex + offset) % pokemon.count + pokemon.count) % pokemon.count
    characterIndex = 0
    resetNameProgress()
    loadStrokes(startingAt: 0)
  }

  func selectCharacter(at index: Int) {
    guard characters.indices.contains(index) else {
      return
    }

    cancelPendingWork()
    // 選び直した文字はもう一度書かせるため、済みの記録から外す。
    nameProgress.reopen(at: index)
    loadStrokes(startingAt: index)
  }

  /// なぞり終えた軌跡 (109 座標系) を判定し、成功なら次の画・次の文字へ進める。
  @discardableResult
  func finishTrace(_ trace: [CGPoint]) -> Bool {
    guard result == nil, strokes.indices.contains(strokeIndex) else {
      return false
    }
    guard StrokeTraceJudge.isTraced(trace: trace, stroke: strokes[strokeIndex]) else {
      failureCount += 1
      message = KakiRenshuMessage.traceAgain
      return false
    }

    strokeIndex += 1
    guard strokeIndex >= strokes.count else {
      message = KakiRenshuMessage.traceStroke(number: strokeIndex + 1)
      return true
    }

    guard characters.indices.contains(characterIndex) else {
      return true
    }
    let character = characters[characterIndex]
    markWritten(character)
    nameProgress.markWritten(at: characterIndex)
    message = KakiRenshuMessage.characterWritten
    SpeechSynthesizer.shared.speak(String(character))

    advanceTask = Task {
      try? await Task.sleep(for: .milliseconds(800))
      guard !Task.isCancelled else {
        return
      }

      advanceToNextCharacterOrFinish()
    }
    return true
  }

  /// ゲット演出を閉じて、次のポケモンの名前へ進む。
  func dismissResult() {
    result = nil
    showPokemon(offsetBy: 1)
  }

  func speakCurrentCharacter() {
    guard characters.indices.contains(characterIndex) else {
      return
    }

    SpeechSynthesizer.shared.speak(String(characters[characterIndex]))
  }

  /// 名前に残っている文字があればそこへ進み、無ければ書き終えた扱いにする。
  ///
  /// 文字はタップで選び直せるため、今の位置ではなく名前全体の進み具合でゲットを確定する。
  private func advanceToNextCharacterOrFinish() {
    guard let nextCharacterIndex = nameProgress.firstUnfinishedIndex else {
      finishName()
      return
    }

    loadStrokes(startingAt: nextCharacterIndex)
  }

  private func markWritten(_ character: Character) {
    try? progressStore?.markWritten(character: character)
    writtenCharacters.insert(KatakanaCharacterNormalizer.baseCharacter(from: character))
  }

  private func finishName() {
    guard let currentPokemon else {
      return
    }

    // 保存できていないのに「とうろく したよ」と見せないため、保存の成否を演出へ渡す。
    var isRegistered = true
    do {
      try progressStore?.markPokemonCaught(id: currentPokemon.id)
    } catch {
      isRegistered = false
    }

    message = isRegistered ? KakiRenshuMessage.nameWritten : KakiRenshuMessage.registerFailed
    result = KakiRenshuResult(pokemon: currentPokemon, isRegistered: isRegistered)
    SpeechSynthesizer.shared.speak(currentPokemon.japaneseName)
  }

  /// `startIndex` 以降で書き順データのある文字を探し、その文字のなぞりを始める。
  ///
  /// ニドラン♀ の「♀」のように KanjiVG に書き順データが無い文字だけを飛ばす。通信の失敗は飛ばさずに
  /// 案内を出して止まる (飛ばすと一画も書いていない文字を書けた扱いにしてしまうため)。
  private func loadStrokes(startingAt startIndex: Int) {
    strokeLoadingTask?.cancel()
    strokes = []
    strokeIndex = 0
    characterIndex = min(max(startIndex, 0), max(characters.count - 1, 0))
    message = KakiRenshuMessage.loading

    let characters = self.characters
    strokeLoadingTask = Task {
      var index = startIndex
      while index < characters.count {
        let strokeData = await strokeData(for: characters[index])
        guard !Task.isCancelled else {
          return
        }

        switch strokeData {
        case .strokes(let loadedStrokes):
          characterIndex = index
          strokes = loadedStrokes
          strokeIndex = 0
          message = KakiRenshuMessage.traceFromFirstStroke
          return
        case .unsupported:
          nameProgress.markSkipped(at: index)
          index += 1
        case .temporaryFailure:
          characterIndex = index
          message = KakiRenshuMessage.strokeLoadFailed
          return
        }
      }

      guard !Task.isCancelled else {
        return
      }

      if let nextCharacterIndex = nameProgress.firstUnfinishedIndex {
        // 名前の前方に書けていない文字が残っているため、そちらへ戻る。
        loadStrokes(startingAt: nextCharacterIndex)
      } else if nameProgress.hasWrittenCharacter {
        finishName()
      } else {
        message = KakiRenshuMessage.strokeDataUnavailable
      }
    }
  }

  private func strokeData(for character: Character) async -> StrokeDataResult {
    if let cached = parsedStrokes[character] {
      return .strokes(cached)
    }
    if unsupportedCharacters.contains(character) {
      return .unsupported
    }
    guard let strokeCache else {
      return .temporaryFailure
    }

    let data: Data
    do {
      data = try await strokeCache.strokeData(for: character)
    } catch {
      guard KanjiVGStrokeAvailability.isUnsupported(error) else {
        return .temporaryFailure
      }

      unsupportedCharacters.insert(character)
      return .unsupported
    }

    guard let parsed = try? KanjiVGStrokeParser.strokes(from: data), !parsed.isEmpty else {
      return .temporaryFailure
    }

    parsedStrokes[character] = parsed
    return .strokes(parsed)
  }

  private func resetNameProgress() {
    nameProgress = NameWritingProgress(characterCount: characters.count)
  }

  private func cancelPendingWork() {
    advanceTask?.cancel()
    advanceTask = nil
    strokeLoadingTask?.cancel()
    strokeLoadingTask = nil
  }
}

/// 1 文字ぶんの書き順データを取りに行った結果。
///
/// 「書き順データが無い文字」と「取り直せば取れるかもしれない失敗」を分けて、後者で文字を飛ばさないようにする。
private enum StrokeDataResult {
  case strokes([StrokePath])
  /// KanjiVG に書き順データが無い文字 (ニドラン♀ の「♀」等)。
  case unsupported
  /// 通信の失敗など、時間をおけば取れる可能性があるもの。
  case temporaryFailure
}

/// 名前 1 つぶんの進み具合。どの文字を書き終えたか、書き順データが無くて飛ばしたかを持つ。
///
/// 文字はタップで選び直せるため、「今どの文字にいるか」ではなくこの進み具合でゲットを確定する。
struct NameWritingProgress: Equatable {
  let characterCount: Int
  private(set) var writtenIndices: Set<Int> = []
  private(set) var skippedIndices: Set<Int> = []

  mutating func markWritten(at index: Int) {
    skippedIndices.remove(index)
    writtenIndices.insert(index)
  }

  mutating func markSkipped(at index: Int) {
    guard !writtenIndices.contains(index) else {
      return
    }

    skippedIndices.insert(index)
  }

  /// 書き直しのために、その文字を未完了へ戻す。
  mutating func reopen(at index: Int) {
    writtenIndices.remove(index)
    skippedIndices.remove(index)
  }

  /// まだ書けても飛ばしてもいない最初の文字の位置。すべて済んでいれば nil。
  var firstUnfinishedIndex: Int? {
    (0..<characterCount).first { !writtenIndices.contains($0) && !skippedIndices.contains($0) }
  }

  /// 1 文字でも書けたか。書き順データが無い文字ばかりの名前をゲット扱いにしないために見る。
  var hasWrittenCharacter: Bool {
    !writtenIndices.isEmpty
  }
}

/// KanjiVG の取得・解析の失敗を、飛ばしてよい文字か取り直せる失敗かに分ける。
///
/// 通信の失敗を「書き順データが無い文字」として飛ばすと、一画も書いていない文字を書けた扱いにしてしまう。
enum KanjiVGStrokeAvailability {
  static func isUnsupported(_ error: any Error) -> Bool {
    guard let cacheError = error as? KanjiVGCacheError else {
      return false
    }

    return switch cacheError {
    case .unsupportedCharacter, .httpStatus(404): true
    case .cachesDirectoryNotFound, .invalidResponse, .httpStatus: false
    }
  }
}
