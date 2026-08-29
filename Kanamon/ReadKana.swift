import Foundation
import SwiftData

/// クイズで正解して読めるようになったカタカナ 1 文字を表す。
/// 読めた事実と日時だけを端末内に保存し、五十音表そのものは `Gojuon` が持つ。
/// 読めたことを取り消す仕様がないため更新用のドメインメソッドを持たず、`updatedDateTime` も宣言しない。
@Model
final class ReadKana {
  @Attribute(.unique) private(set) var kana: String
  private(set) var createdDateTime: Date = Date.now

  init(kana: String, createdDateTime: Date = .now) {
    self.kana = kana
    self.createdDateTime = createdDateTime
  }
}

/// 五十音表の 46 文字。もじ ずかんの並びと、あなぬけのダミー選択肢に使う。
enum Gojuon {
  static let characters: [Character] = Array(
    "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"
  )
}

/// 濁点・半濁点・小書き文字を、五十音表にある元の文字へ寄せる。
enum KanaNormalizer {
  private static let smallKana: [Character: Character] = [
    "ァ": "ア", "ィ": "イ", "ゥ": "ウ", "ェ": "エ", "ォ": "オ",
    "ャ": "ヤ", "ュ": "ユ", "ョ": "ヨ", "ッ": "ツ",
  ]

  /// 濁点・半濁点を外し、小書き文字を大きい文字へ置き換えた 1 文字を返す。
  static func base(of character: Character) -> Character {
    if let large = smallKana[character] {
      return large
    }

    let scalars = String(character)
      .decomposedStringWithCanonicalMapping
      .unicodeScalars
      .filter { $0.value != 0x3099 && $0.value != 0x309A }
    guard scalars.count == 1, let scalar = scalars.first else {
      return character
    }

    return smallKana[Character(scalar)] ?? Character(scalar)
  }

  /// 名前のうち、五十音表の 46 文字として読める文字を返す。「ー」のように五十音表にない文字は含めない。
  static func readableKana(in name: String) -> Set<Character> {
    let gojuon = Set(Gojuon.characters)
    return Set(name.map(base(of:)).filter(gojuon.contains))
  }
}

/// 読めた文字を SwiftData へ保存し、もじ ずかんへ読み出す。
@MainActor
final class ReadKanaStore {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  /// 保存済みの読めた文字を返す。
  func readKana() throws -> Set<Character> {
    let descriptor = FetchDescriptor<ReadKana>()
    return Set(try modelContext.fetch(descriptor).compactMap(\.kana.first))
  }

  /// 名前に含まれる読める文字をすべて読めたことにする。保存済みの文字は追加しないため、繰り返し呼んでも結果は変わらない。
  func markRead(name: String) throws {
    let added = try KanaNormalizer.readableKana(in: name).subtracting(readKana())
    guard !added.isEmpty else {
      return
    }

    for kana in added {
      modelContext.insert(ReadKana(kana: String(kana)))
    }
    try modelContext.save()
  }
}
