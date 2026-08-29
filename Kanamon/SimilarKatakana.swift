import Foundation

/// 形がにていて読み間違えやすいカタカナ 1 文字と、その見分け方の説明を表す。
private struct SimilarKatakanaEntry {
  let character: Character
  /// 見分け方の 1 行。子どもが読めるようにひらがな・カタカナと空白だけで書く。
  let description: String
}

/// 形がにているカタカナ 2 文字を 1 組として表す。
private struct SimilarKatakanaPair {
  let first: SimilarKatakanaEntry
  let second: SimilarKatakanaEntry
}

/// 形がにているカタカナの組を保持し、タップされた文字の見分け方を組み立てる。
///
/// 対象はデザイン仕様 (documents/design/README.md「3. 学習になる読み練習」) が挙げる 8 組。
enum SimilarKatakana {
  private static let pairs: [SimilarKatakanaPair] = [
    SimilarKatakanaPair(
      first: SimilarKatakanaEntry(character: "シ", description: "シ は てんてん が よこむき"),
      second: SimilarKatakanaEntry(character: "ツ", description: "ツ は てんてん が たてむき")
    ),
    SimilarKatakanaPair(
      first: SimilarKatakanaEntry(character: "ソ", description: "ソ は みじかい ぼう が たて"),
      second: SimilarKatakanaEntry(character: "ン", description: "ン は よこ から はらう")
    ),
    SimilarKatakanaPair(
      first: SimilarKatakanaEntry(character: "ク", description: "ク は かど が するどい"),
      second: SimilarKatakanaEntry(character: "ケ", description: "ケ は よこぼう が ある")
    ),
    SimilarKatakanaPair(
      first: SimilarKatakanaEntry(character: "ス", description: "ス は はらい だけ"),
      second: SimilarKatakanaEntry(character: "ヌ", description: "ヌ は てん が ある")
    ),
    SimilarKatakanaPair(
      first: SimilarKatakanaEntry(character: "マ", description: "マ は よこぼう が うえ"),
      second: SimilarKatakanaEntry(character: "ム", description: "ム は さんかく の かたち")
    ),
    SimilarKatakanaPair(
      first: SimilarKatakanaEntry(character: "ナ", description: "ナ は じゅうじ の かたち"),
      second: SimilarKatakanaEntry(character: "メ", description: "メ は ばってん の かたち")
    ),
    SimilarKatakanaPair(
      first: SimilarKatakanaEntry(character: "ハ", description: "ハ は ふたつ に わかれる"),
      second: SimilarKatakanaEntry(character: "ヘ", description: "ヘ は ひとつ の やま")
    ),
    SimilarKatakanaPair(
      first: SimilarKatakanaEntry(character: "チ", description: "チ は うえ が ななめ"),
      second: SimilarKatakanaEntry(character: "テ", description: "テ は よこぼう が ふたつ")
    ),
  ]

  static func isSimilar(character: Character) -> Bool {
    tip(character: character) != nil
  }

  /// タップされた文字の説明を先に、相手の文字の説明を後に並べた 2 行を返す。組にない文字は nil。
  static func tip(character: Character) -> String? {
    for pair in pairs {
      if pair.first.character == character {
        return "\(pair.first.description)\n\(pair.second.description)"
      }
      if pair.second.character == character {
        return "\(pair.second.description)\n\(pair.first.description)"
      }
    }

    return nil
  }

  /// にている もじ として登録されている全 16 文字。テストと画面の検証に使う。
  static var allCharacters: [Character] {
    pairs.flatMap { [$0.first.character, $0.second.character] }
  }
}
