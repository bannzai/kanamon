import Foundation

/// クイズの出題形式。1 問ごとに 4 たく → あなぬけ → なまえ から え の順で切り替える。
///
/// 表示用の文言は持たせず (`.claude/rules/coding-rules-entity.md`)、画面側の switch で組み立てる。
enum QuizMode: CaseIterable {
  /// え を見て なまえ を 4 つから選ぶ。
  case nameChoice
  /// なまえ の 1 文字を隠し、入る文字を 4 つから選ぶ。
  case fillInBlank
  /// なまえ を読んで え を 4 つから選ぶ。
  case imageChoice

  var next: QuizMode {
    switch self {
    case .nameChoice: .fillInBlank
    case .fillInBlank: .imageChoice
    case .imageChoice: .nameChoice
    }
  }
}

/// 五十音表の 46 文字。あなぬけのダミー選択肢と、読めた文字として記録する対象の判定に使う。
enum Gojuon {
  static let characters: [Character] = Array(
    "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"
  )

  /// 子どもが見分けにくい形の似た文字の組 (documents/design/README.md「にている もじ の注意」)。
  static let similarPairs: [Set<Character>] = [
    ["シ", "ツ"], ["ソ", "ン"], ["ク", "ケ"], ["ス", "ヌ"],
    ["マ", "ム"], ["ナ", "メ"], ["ハ", "ヘ"], ["チ", "テ"],
  ]

  /// 指定した文字と形が似ている文字を返す。似た文字が無ければ空。
  static func similarCharacters(to character: Character) -> [Character] {
    similarPairs
      .filter { $0.contains(character) }
      .flatMap { $0.subtracting([character]) }
  }

  /// 名前のうち、五十音表の 46 文字として読める文字を正規化して返す。「ー」のように五十音表にない文字は含めない。
  static func readableCharacters(in name: String) -> Set<Character> {
    let gojuon = Set(characters)
    return Set(name.map(KatakanaCharacterNormalizer.baseCharacter(from:)).filter(gojuon.contains))
  }
}

/// 1 問分の出題内容。
struct QuizQuestion: Equatable {
  let mode: QuizMode
  let answer: Pokemon
  /// 4 たく・なまえ から え の選択肢 (4 匹、正解を含む、重複なし、シャッフル済み)。あなぬけでは空。
  let pokemonChoices: [Pokemon]
  /// あなぬけで ？ にする文字の位置 (`answer.japaneseName` の Character index)。他モードは nil。
  let blankIndex: Int?
  /// あなぬけの選択肢 (4 文字、正解を含む、重複なし、シャッフル済み)。他モードは空。
  let kanaChoices: [Character]
}

/// 型を隠したまま乱数生成器を持ち回すためのラッパー。テストで固定シードの生成器へ差し替える。
struct AnyRandomNumberGenerator: RandomNumberGenerator {
  private var base: any RandomNumberGenerator

  init(_ base: some RandomNumberGenerator) {
    self.base = base
  }

  mutating func next() -> UInt64 {
    base.next()
  }
}

/// 出題するポケモンとモードを決める。乱数は差し替え可能にしてテストで固定する。
struct QuizQuestionGenerator {
  /// 未ゲットのポケモンを選ぶ確率 (パーセント)。残りはゲット済みからの復習に使う。
  private static let notCaughtPercentage = 80

  private let pokemons: [Pokemon]
  private let caughtPokemonIDs: Set<Int>
  private var generator: AnyRandomNumberGenerator

  init(
    pokemons: [Pokemon],
    caughtPokemonIDs: Set<Int>,
    generator: some RandomNumberGenerator = SystemRandomNumberGenerator()
  ) {
    self.pokemons = pokemons
    self.caughtPokemonIDs = caughtPokemonIDs
    self.generator = AnyRandomNumberGenerator(generator)
  }

  /// ダミーを 3 匹そろえられない (4 匹未満) 場合と、あなぬけで穴にできるかな文字を持つポケモンがいない場合は nil を返す。
  mutating func makeQuestion(mode: QuizMode) -> QuizQuestion? {
    let candidates =
      switch mode {
      case .nameChoice, .imageChoice: pokemons
      case .fillInBlank: pokemons.filter { $0.japaneseName.contains(where: Self.isBlankable) }
      }
    guard pokemons.count >= 4, let answer = pickAnswer(from: candidates) else {
      return nil
    }

    switch mode {
    case .nameChoice, .imageChoice:
      return QuizQuestion(
        mode: mode,
        answer: answer,
        pokemonChoices: pickPokemonChoices(answer: answer),
        blankIndex: nil,
        kanaChoices: []
      )
    case .fillInBlank:
      guard let blank = pickBlank(name: answer.japaneseName) else {
        return nil
      }
      return QuizQuestion(
        mode: mode,
        answer: answer,
        pokemonChoices: [],
        blankIndex: blank.index,
        kanaChoices: blank.choices
      )
    }
  }

  /// 穴にできる文字か。読みとして扱えるカタカナ (U+30A1〜U+30FA) だけを対象にし、
  /// 長音符「ー」や「ニドラン♀」「ニドラン♂」の記号は除外する。
  static func isBlankable(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { (0x30A1...0x30FA).contains($0.value) }
  }

  private mutating func pickAnswer(from candidates: [Pokemon]) -> Pokemon? {
    let notCaught = candidates.filter { !caughtPokemonIDs.contains($0.id) }
    let caught = candidates.filter { caughtPokemonIDs.contains($0.id) }

    if notCaught.isEmpty {
      return caught.randomElement(using: &generator)
    }
    if caught.isEmpty {
      return notCaught.randomElement(using: &generator)
    }

    return Int.random(in: 0..<100, using: &generator) < Self.notCaughtPercentage
      ? notCaught.randomElement(using: &generator)
      : caught.randomElement(using: &generator)
  }

  private mutating func pickPokemonChoices(answer: Pokemon) -> [Pokemon] {
    let dummies = pokemons
      .filter { $0.id != answer.id }
      .shuffled(using: &generator)
      .prefix(3)
    return ([answer] + dummies).shuffled(using: &generator)
  }

  private mutating func pickBlank(name: String) -> (index: Int, choices: [Character])? {
    let characters = Array(name)
    guard !characters.isEmpty else {
      return nil
    }

    guard let index = characters.indices.filter({ Self.isBlankable(characters[$0]) }).randomElement(using: &generator) else {
      return nil
    }
    let correct = characters[index]
    // にている文字の弁別が練習になるよう (documents/design/README.md「クイズ」)、正解と形が似た文字を先にダミーへ入れ、残りを五十音から補う。
    let similar = Gojuon.similarCharacters(to: correct).shuffled(using: &generator)
    let others = Gojuon.characters
      .filter { $0 != correct && !similar.contains($0) }
      .shuffled(using: &generator)
    let dummies = (similar + others).prefix(3)
    return (index, ([correct] + dummies).shuffled(using: &generator))
  }
}
