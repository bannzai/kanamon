import Foundation

/// なまえ づくりで 1 匹ぶんの出題状態を表す。
///
/// 画面から切り離した純粋な値型にして、並べ方の判定だけをユニットテストできるようにする。
struct NameBuilderGame: Equatable {
  /// 組み立てる名前を 1 文字ずつに分けたもの。空きマスの数でもある。
  let answer: [Character]
  /// 下に並べる文字タイル。正解の文字とダミーの文字をシャッフルした並びで持つ。
  let tiles: [Character]
  /// いま並べた文字。先頭のマスから順に埋まる。
  private(set) var placed: [Character] = []

  /// 全マスが埋まっているか。
  var isFilled: Bool {
    placed.count == answer.count
  }

  /// タイル 1 つぶんの表示状態。同じ文字が複数並ぶため、文字ではなく並びの位置で区別する。
  struct Tile: Identifiable, Equatable {
    /// `tiles` の何番目かを表す。同じ文字のタイルを見分けるために使う。
    let id: Int
    /// タイルに書かれているカタカナ。
    let character: Character
    /// すでに使い切っていて、これ以上タップできない状態か。
    let isSpent: Bool
  }

  /// 表示用のタイル一覧。同じ文字が名前に 2 回出る場合に備え、使用済みフラグではなく使用回数で判定する。
  var tileStates: [Tile] {
    var placedCounts: [Character: Int] = [:]
    for character in placed {
      placedCounts[character, default: 0] += 1
    }

    var seenCounts: [Character: Int] = [:]
    return tiles.enumerated().map { index, character in
      seenCounts[character, default: 0] += 1
      return Tile(
        id: index,
        character: character,
        isSpent: placedCounts[character, default: 0] >= seenCounts[character, default: 0]
      )
    }
  }

  /// 全マスが埋まった時の判定結果。
  enum Judgement: Equatable {
    /// 並びが名前と一致した。
    case correct
    /// 誤りがあった時に、先頭から合っている文字数だけ残して戻す。全部消さないための結果。
    case rollback(keepCount: Int)
  }

  /// 全マスが埋まっていれば判定する。埋まっていなければ判定しない (`nil` を返す)。
  ///
  /// 状態を変えない読み取りのため何度呼んでも同じ結果になる。戻す操作は `rollback(keepCount:)` で行う。
  func judgement() -> Judgement? {
    guard isFilled else {
      return nil
    }
    guard placed != answer else {
      return .correct
    }

    var keepCount = 0
    while keepCount < placed.count, placed[keepCount] == answer[keepCount] {
      keepCount += 1
    }
    return .rollback(keepCount: keepCount)
  }

  /// タイルをタップして、先頭から数えて次の空きマスを埋める。
  ///
  /// 呼ぶたびに 1 文字増えるため冪等ではない。使い切ったタイルと、全マスが埋まっている時は何もしない。
  mutating func place(tile: Tile) {
    guard !tile.isSpent, !isFilled else {
      return
    }
    placed.append(tile.character)
  }

  /// 「1 つ もどす」で直前の 1 文字を取り消す。
  ///
  /// 呼ぶたびに 1 文字減るため冪等ではない。まだ並べていない時は何もしない。
  mutating func undo() {
    guard !placed.isEmpty else {
      return
    }
    placed.removeLast()
  }

  /// 埋めたマスをタップして、その位置から後ろをまとめて取り消す。
  ///
  /// 同じ位置を指定すれば結果は同じになる (冪等)。
  mutating func removePlaced(index: Int) {
    guard placed.indices.contains(index) else {
      return
    }
    placed.removeSubrange(index...)
  }

  /// 先頭から `keepCount` 文字だけ残して戻す。`judgement()` の `.rollback` に対応する。
  ///
  /// 同じ `keepCount` で何度呼んでも結果は同じになる (冪等)。
  mutating func rollback(keepCount: Int) {
    placed = Array(placed.prefix(max(0, keepCount)))
  }
}

/// 名前からタイルの並びを組み立てる。正解の文字にダミーの文字を混ぜてシャッフルする。
enum NameBuilderTileMaker {
  /// 名前の文字数に対して混ぜるダミー文字の数。
  ///
  /// タイルの総数が 10 枚に収まる範囲でダミーを混ぜる (デザイン仕様「4-2. なまえ づくり」の 3〜6 文字)。
  /// 短い名前ほど当てずっぽうで並んでしまうため、上限の 6 文字まで増やす。
  static func decoyCount(answerLength: Int) -> Int {
    max(3, min(6, 10 - answerLength))
  }

  /// 正解の文字 + ダミー文字をシャッフルしたタイルの並びを作る。
  ///
  /// - Parameters:
  ///   - answer: 組み立てる名前を 1 文字ずつに分けたもの。
  ///   - candidates: ダミーに使う文字の候補。既定は五十音の 46 文字で、まだ習っていない濁点付きの文字を混ぜないため。
  ///   - shuffle: 並びを混ぜる処理。既定は `shuffled()` で、テストから並びを固定できるように引数にしている。
  static func tiles(
    answer: [Character],
    candidates: [Character] = KatakanaSyllabary.characters,
    shuffle: ([Character]) -> [Character] = { $0.shuffled() }
  ) -> [Character] {
    shuffle(
      answer
        + shuffle(candidates.filter { !answer.contains($0) })
        .prefix(decoyCount(answerLength: answer.count))
    )
  }
}
