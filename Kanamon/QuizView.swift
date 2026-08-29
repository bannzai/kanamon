import SwiftUI
import UIKit

/// クイズ画面に出す文言。子どもが読めるようにひらがな・カタカナ・数字だけで書く。
enum QuizText {
  static let title = "クイズ"
  static let speak = "よんで もらう"
  static let next = "つぎ へ"
  static let tryAgain = "もう いちど"
  static let getHeadline = "ゲット！"
  static let correctHeadline = "せいかい！"
  static let registered = "ずかん に とうろく したよ"
  static let alreadyRegistered = "もう ずかん に いるよ"
  static let stamp = "とうろく"
  static let loading = "よみこみちゅう"
  static let failed = "よみこめなかったよ"
  static let retry = "もういちど"

  static func modeName(_ mode: QuizMode) -> String {
    switch mode {
    case .nameChoice: "4たく"
    case .fillInBlank: "あなぬけ"
    case .imageChoice: "なまえ から え"
    }
  }

  static func prompt(_ mode: QuizMode) -> String {
    switch mode {
    case .nameChoice: "なまえ は どれ かな？"
    case .fillInBlank: "どの もじ が はいる かな？"
    case .imageChoice: "この なまえ の モンスター は どれ？"
    }
  }

  /// 画面に出すすべての文言。かなだけで書けているかをテストで検証するために並べる。
  static let all: [String] =
    [
      title, speak, next, tryAgain, getHeadline, correctHeadline,
      registered, alreadyRegistered, stamp, loading, failed, retry,
    ] + QuizMode.allCases.map(modeName) + QuizMode.allCases.map(prompt)
}

/// クイズ画面のデザイントークン。
enum QuizColor {
  static let ink = Color(hexadecimal: 0x33_241A)
  static let cream = Color(hexadecimal: 0xFF_F6E3)
  static let background = Color(hexadecimal: 0xFF_EDE8)
  static let yellow = Color(hexadecimal: 0xFF_C22E)
  static let blue = Color(hexadecimal: 0x2B_A9FF)
  static let green = Color(hexadecimal: 0x4C_C66A)
  static let red = Color(hexadecimal: 0xD9_3B2B)
  /// 不正解の選択肢の背景。
  static let wrong = Color(hexadecimal: 0xFF_D9D2)
  /// あなぬけで ？ にしている場所の背景。
  static let blank = Color(hexadecimal: 0xFF_F1CF)
  /// ゲット演出の背景で回す光。
  static let ray = Color(hexadecimal: 0xFF_D86B)
  static let confetti: [Color] = [
    Color(hexadecimal: 0xFF_5A3C),
    blue,
    green,
    Color(hexadecimal: 0xFF_9FC4),
    .white,
    red,
  ]
}

/// え と なまえ を結びつけるクイズを 3 つの形式で出す画面。
///
/// `QuizModel` は `modelContext` から組み立てるため、`.task` で作ってから中身を表示する。
struct QuizView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var model: QuizModel?

  var body: some View {
    ZStack {
      QuizColor.background.ignoresSafeArea()
      if let model {
        QuizContentView(model: model)
      } else {
        QuizStatusView<ProgressView, EmptyView>(text: QuizText.loading) { ProgressView() }
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .task {
      guard model == nil else {
        return
      }
      model = QuizModel(modelContext: modelContext)
    }
  }
}

/// 選択肢ボタンの見た目。正解・不正解の反応を表す。
private enum QuizChoiceHighlight {
  case normal
  case correct
  case wrong
}

/// `QuizModel` の状態を実際に描く画面本体。
private struct QuizContentView: View {
  let model: QuizModel

  @Environment(\.dismiss) private var dismiss
  @State private var wrongChoiceID: String?
  @State private var wrongOffset: CGFloat = 0
  @State private var correctChoiceID: String?
  @State private var correctScale: CGFloat = 1
  @State private var overlay = false
  /// 正解から演出までの待ち時間を担う Task。次の問題へ進む・画面を閉じる時に取り消して、古い解答の演出を出さない。
  @State private var revealTask: Task<Void, Never>?

  private static let columns = [
    GridItem(.flexible(), spacing: 14),
    GridItem(.flexible(), spacing: 14),
  ]

  var body: some View {
    ZStack {
      switch model.state {
      case .loading:
        QuizStatusView(text: QuizText.loading, backButton: backButton) { ProgressView() }
      case .failed:
        QuizStatusView(text: QuizText.failed, backButton: backButton) {
          Button {
            Task { await model.retryLoad() }
          } label: {
            Text(QuizText.retry)
              .font(.system(size: 26, weight: .heavy, design: .rounded))
              .foregroundStyle(.white)
              .padding(.horizontal, 32)
              .frame(minHeight: 72)
              .background(QuizColor.blue, in: Capsule())
          }
          .buttonStyle(.plain)
        }
      case .loaded:
        quiz
      }

      if overlay, let result = model.result {
        QuizGetOverlay(result: result, imageCache: model.imageCache, onNext: advance)
          .transition(.opacity)
      }
    }
    .task { await model.load() }
    .onChange(of: model.result) { _, result in
      revealTask?.cancel()
      guard let result else {
        overlay = false
        return
      }
      revealTask = Task {
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled, model.result == result else {
          return
        }
        SpeechSynthesizer.shared.speak(result.pokemon.japaneseName)
        withAnimation(.easeOut(duration: 0.28)) { overlay = true }
      }
    }
    .onDisappear { revealTask?.cancel() }
  }

  @ViewBuilder
  private var quiz: some View {
    if let question = model.question {
      VStack(spacing: 0) {
        header(question: question)
        ScrollView {
          VStack(spacing: 20) {
            stage(question: question)
            Text(QuizText.prompt(question.mode))
              .font(.system(size: 22, weight: .heavy, design: .rounded))
              .foregroundStyle(QuizColor.ink)
            choices(question: question)
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 32)
        }
      }
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 20)
          .onEnded { value in
            let horizontal = abs(value.translation.width)
            let vertical = abs(value.translation.height)
            // 選択肢まで縦スクロールする指の動きを誤ってページ送りにしないよう、横が縦の 2 倍以上の時だけ送る。
            guard horizontal >= 60, horizontal >= vertical * 2 else {
              return
            }
            advance()
          }
      )
    }
  }

  /// ホームへ戻るボタン。ナビゲーションバーを隠しているため、読み込み中・失敗時にも必ず出す。
  private var backButton: some View {
    Button {
      dismiss()
    } label: {
      Image(systemName: "chevron.left")
        .font(.system(size: 22, weight: .heavy))
        .foregroundStyle(QuizColor.ink)
        .frame(width: 50, height: 50)
        .background(QuizColor.cream, in: Circle())
        .overlay(Circle().strokeBorder(QuizColor.ink, lineWidth: 4))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("quiz_back_button")
  }

  private func header(question: QuizQuestion) -> some View {
    HStack(spacing: 10) {
      backButton

      Text(QuizText.title)
        .font(.system(size: 30, weight: .heavy, design: .rounded))
        .foregroundStyle(QuizColor.ink)

      Spacer(minLength: 0)

      VStack(alignment: .trailing, spacing: 4) {
        Text(QuizText.modeName(question.mode))
          .font(.system(size: 15, weight: .heavy, design: .rounded))
          .foregroundStyle(QuizColor.ink)
          .padding(.horizontal, 14)
          .padding(.vertical, 7)
          .background(QuizColor.yellow, in: Capsule())
          .overlay(Capsule().strokeBorder(QuizColor.ink, lineWidth: 3))
        Text(String(format: "No.%03d", question.answer.id))
          .font(.system(size: 14, weight: .heavy, design: .rounded))
          .foregroundStyle(QuizColor.ink.opacity(0.7))
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }

  @ViewBuilder
  private func stage(question: QuizQuestion) -> some View {
    switch question.mode {
    case .nameChoice:
      spriteCard(pokemon: question.answer)
    case .fillInBlank:
      VStack(spacing: 14) {
        spriteCard(pokemon: question.answer)
        nameRow(question: question)
      }
    case .imageChoice:
      nameCard(pokemon: question.answer)
    }
  }

  private func spriteCard(pokemon: Pokemon) -> some View {
    QuizSpriteImage(pokemon: pokemon, imageCache: model.imageCache, size: 212)
      .frame(maxWidth: .infinity, minHeight: 236, maxHeight: 236)
      .background(QuizColor.cream, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 30, style: .continuous)
          .strokeBorder(QuizColor.ink, lineWidth: 5)
      )
      .quizSolidShadow(cornerRadius: 30, offset: 7)
  }

  private func nameRow(question: QuizQuestion) -> some View {
    let characters = Array(question.answer.japaneseName)
    return HStack(spacing: 5) {
      ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
        nameCell(character: character, blank: index == question.blankIndex)
      }
    }
  }

  private func nameCell(character: Character, blank: Bool) -> some View {
    let hidden = blank && !model.answered
    return VStack(spacing: 1) {
      Text(hidden ? "？" : String(character))
        .font(.system(size: 28, weight: .heavy, design: .rounded))
        .foregroundStyle(QuizColor.ink)
      Text(hidden ? " " : KatakanaConverter.hiragana(from: String(character)))
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundStyle(QuizColor.blue)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.5)
    .frame(maxWidth: .infinity, minHeight: 64)
    .background(nameCellBackground(blank: blank), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      if hidden {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(QuizColor.ink, style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
      } else {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(QuizColor.ink, lineWidth: 3)
      }
    }
    .shadow(color: blank && model.answered ? QuizColor.yellow : .clear, radius: 10)
  }

  private func nameCellBackground(blank: Bool) -> Color {
    guard blank else {
      return QuizColor.cream
    }
    return model.answered ? QuizColor.yellow : QuizColor.blank
  }

  private func nameCard(pokemon: Pokemon) -> some View {
    VStack(spacing: 16) {
      Text(pokemon.japaneseName)
        .font(.system(size: 46, weight: .heavy, design: .rounded))
        .foregroundStyle(QuizColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.4)
      Button {
        SpeechSynthesizer.shared.speak(pokemon.japaneseName)
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 22, weight: .heavy))
          Text(QuizText.speak)
            .font(.system(size: 22, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 26)
        .frame(minHeight: 62)
        .background(QuizColor.blue, in: Capsule())
        .overlay(Capsule().strokeBorder(QuizColor.ink, lineWidth: 4))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("quiz_speak_button")
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 236)
    .background(QuizColor.cream, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 30, style: .continuous)
        .strokeBorder(QuizColor.ink, lineWidth: 5)
    )
    .quizSolidShadow(cornerRadius: 30, offset: 7)
  }

  @ViewBuilder
  private func choices(question: QuizQuestion) -> some View {
    LazyVGrid(columns: Self.columns, spacing: 14) {
      switch question.mode {
      case .nameChoice:
        ForEach(Array(question.pokemonChoices.enumerated()), id: \.element.id) { index, pokemon in
          choiceButton(index: index, id: QuizModel.choiceID(pokemon: pokemon), minHeight: 88) {
            choose(pokemon: pokemon)
          } label: {
            Text(pokemon.japaneseName)
              .font(.system(size: 26, weight: .heavy, design: .rounded))
              .lineLimit(1)
              .minimumScaleFactor(0.4)
          }
        }
      case .imageChoice:
        ForEach(Array(question.pokemonChoices.enumerated()), id: \.element.id) { index, pokemon in
          choiceButton(index: index, id: QuizModel.choiceID(pokemon: pokemon), minHeight: 110) {
            choose(pokemon: pokemon)
          } label: {
            QuizSpriteImage(pokemon: pokemon, imageCache: model.imageCache, size: 94)
          }
        }
      case .fillInBlank:
        ForEach(Array(question.kanaChoices.enumerated()), id: \.element) { index, kana in
          choiceButton(index: index, id: QuizModel.choiceID(kana: kana), minHeight: 88) {
            choose(kana: kana)
          } label: {
            Text(String(kana))
              .font(.system(size: 38, weight: .heavy, design: .rounded))
          }
        }
      }
    }
  }

  private func choiceButton(
    index: Int,
    id: String,
    minHeight: CGFloat,
    action: @escaping () -> Void,
    @ViewBuilder label: @escaping () -> some View
  ) -> some View {
    QuizChoiceButton(
      index: index,
      minHeight: minHeight,
      highlight: highlight(id: id),
      scale: correctChoiceID == id ? correctScale : 1,
      offset: wrongChoiceID == id ? wrongOffset : 0,
      action: action,
      label: label
    )
  }

  private func highlight(id: String) -> QuizChoiceHighlight {
    if correctChoiceID == id {
      return .correct
    }
    if wrongChoiceID == id {
      return .wrong
    }
    return .normal
  }

  private func choose(pokemon: Pokemon) {
    guard !model.answered else {
      return
    }
    SpeechSynthesizer.shared.speak(pokemon.japaneseName)
    model.answer(pokemon: pokemon)
    react(id: QuizModel.choiceID(pokemon: pokemon))
  }

  private func choose(kana: Character) {
    guard !model.answered else {
      return
    }
    SpeechSynthesizer.shared.speak(String(kana))
    model.answer(kana: kana)
    react(id: QuizModel.choiceID(kana: kana))
  }

  private func react(id: String) {
    if model.answered {
      Task { await pop(id: id) }
    } else if model.wrongChoiceID == id {
      SpeechSynthesizer.shared.speak(QuizText.tryAgain)
      Task { await shake(id: id) }
    }
  }

  /// 正解の選択肢を 1.09 倍から 1.0 倍へ戻して弾ませる。
  private func pop(id: String) async {
    correctChoiceID = id
    correctScale = 1.09
    try? await Task.sleep(for: .milliseconds(16))
    withAnimation(.spring(response: 0.36, dampingFraction: 0.55)) {
      correctScale = 1
    }
  }

  /// 不正解の選択肢を 0.38 秒かけて横に揺らし、0.46 秒後に元へ戻す。
  private func shake(id: String) async {
    wrongChoiceID = id
    wrongOffset = 0
    withAnimation(.easeInOut(duration: 0.095).repeatCount(4, autoreverses: true)) {
      wrongOffset = 8
    }
    try? await Task.sleep(for: .milliseconds(460))
    guard wrongChoiceID == id else {
      return
    }
    wrongOffset = 0
    wrongChoiceID = nil
  }

  private func advance() {
    revealTask?.cancel()
    overlay = false
    wrongChoiceID = nil
    wrongOffset = 0
    correctChoiceID = nil
    correctScale = 1
    model.advance()
  }
}

/// 読み込み中・読み込み失敗を伝える画面。戻るボタンを渡すと左上に置く。
private struct QuizStatusView<Accessory: View, BackButton: View>: View {
  let text: String
  let backButton: BackButton?
  @ViewBuilder let accessory: () -> Accessory

  init(text: String, backButton: BackButton? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
    self.text = text
    self.backButton = backButton
    self.accessory = accessory
  }

  var body: some View {
    VStack(spacing: 20) {
      accessory()
      Text(text)
        .font(.system(size: 26, weight: .heavy, design: .rounded))
        .foregroundStyle(QuizColor.ink)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .topLeading) {
      if let backButton {
        backButton
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
      }
    }
  }
}

/// 選択肢 1 つ分のボタン。枠と真下のべた影で紙のカードのように見せる。
private struct QuizChoiceButton<Label: View>: View {
  let index: Int
  let minHeight: CGFloat
  let highlight: QuizChoiceHighlight
  let scale: CGFloat
  let offset: CGFloat
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  var body: some View {
    Button(action: action) {
      label()
        .foregroundStyle(highlight == .correct ? Color.white : QuizColor.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(QuizColor.ink, lineWidth: 5)
        )
        .quizSolidShadow(cornerRadius: 26, offset: 7)
    }
    .buttonStyle(.plain)
    .scaleEffect(scale)
    .offset(x: offset)
    .accessibilityIdentifier("quiz_choice_\(index)")
  }

  private var background: Color {
    switch highlight {
    case .normal: QuizColor.cream
    case .correct: QuizColor.green
    case .wrong: QuizColor.wrong
    }
  }
}

/// スプライト画像をキャッシュから読んで表示する。失敗したら少し待って読み直す。
struct QuizSpriteImage: View {
  let pokemon: Pokemon
  let imageCache: PokemonImageCache?
  let size: CGFloat

  @State private var image: UIImage?
  @State private var attempt = 0

  private static let maximumAttempts = 3

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
      } else {
        ProgressView()
      }
    }
    .frame(width: size, height: size)
    .onChange(of: pokemon.id) {
      attempt = 0
    }
    .task(id: "\(pokemon.id)-\(attempt)") {
      await load()
    }
  }

  private func load() async {
    image = nil
    guard let imageCache else {
      return
    }

    do {
      image = UIImage(data: try await imageCache.imageData(for: pokemon))
    } catch {
      guard attempt + 1 < Self.maximumAttempts else {
        return
      }
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled else {
        return
      }
      attempt += 1
    }
  }
}

/// 正解したときに全面へ出すゲット演出。
private struct QuizGetOverlay: View {
  let result: QuizResult
  let imageCache: PokemonImageCache?
  let onNext: () -> Void

  var body: some View {
    ZStack {
      QuizColor.yellow.opacity(0.97).ignoresSafeArea()
      QuizRadialRays()
      QuizConfetti()

      VStack(spacing: 16) {
        Spacer(minLength: 0)
        sprite
        headline
        nameCard
        Text("\(String(format: "No.%03d", result.pokemon.id)) ・ \(result.isNewCatch ? QuizText.registered : QuizText.alreadyRegistered)")
          .font(.system(size: 18, weight: .heavy, design: .rounded))
          .foregroundStyle(QuizColor.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
        Spacer(minLength: 0)
        nextButton
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 28)
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("quiz_get_overlay")
  }

  private var sprite: some View {
    QuizSpriteImage(pokemon: result.pokemon, imageCache: imageCache, size: 172)
      .frame(width: 214, height: 214)
      .background(Color.white, in: Circle())
      .overlay(Circle().strokeBorder(QuizColor.ink, lineWidth: 6))
      .background(Circle().fill(QuizColor.ink).offset(y: 10))
      .overlay(alignment: .topTrailing) {
        if result.isNewCatch {
          stamp.offset(x: 34, y: -10)
        }
      }
  }

  private var stamp: some View {
    Text(QuizText.stamp)
      .font(.system(size: 27, weight: .heavy, design: .rounded))
      .foregroundStyle(QuizColor.red)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(QuizColor.red, lineWidth: 6)
      )
      .rotationEffect(.degrees(-13))
  }

  private var headline: some View {
    Text(result.isNewCatch ? QuizText.getHeadline : QuizText.correctHeadline)
      .font(.system(size: 62, weight: .heavy, design: .rounded))
      .foregroundStyle(.white)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .shadow(color: QuizColor.ink, radius: 0, x: 3, y: 0)
      .shadow(color: QuizColor.ink, radius: 0, x: -3, y: 0)
      .shadow(color: QuizColor.ink, radius: 0, x: 0, y: 3)
      .shadow(color: QuizColor.ink, radius: 0, x: 0, y: -3)
  }

  private var nameCard: some View {
    Text(result.pokemon.japaneseName)
      .font(.system(size: 42, weight: .heavy, design: .rounded))
      .foregroundStyle(QuizColor.ink)
      .lineLimit(1)
      .minimumScaleFactor(0.4)
      .padding(.horizontal, 24)
      .padding(.vertical, 12)
      .background(QuizColor.cream, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .strokeBorder(QuizColor.ink, lineWidth: 5)
      )
      .quizSolidShadow(cornerRadius: 24, offset: 7)
  }

  private var nextButton: some View {
    Button(action: onNext) {
      Text(QuizText.next)
        .font(.system(size: 34, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(QuizColor.green, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 30, style: .continuous)
            .strokeBorder(QuizColor.ink, lineWidth: 5)
        )
        .quizSolidShadow(cornerRadius: 30, offset: 7)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("quiz_next_button")
  }
}

/// ゲット演出の背景で回る放射状の光。
private struct QuizRadialRays: View {
  @State private var angle: Double = 0

  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = Double(max(size.width, size.height))
      let half = Double.pi / 16
      var path = Path()
      for index in 0..<8 {
        let base = Double(index) / 8 * 2 * .pi
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + cos(base - half) * radius, y: center.y + sin(base - half) * radius))
        path.addLine(to: CGPoint(x: center.x + cos(base + half) * radius, y: center.y + sin(base + half) * radius))
        path.closeSubpath()
      }
      context.fill(path, with: .color(QuizColor.ray.opacity(0.8)))
    }
    .rotationEffect(.degrees(angle))
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .onAppear {
      withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
        angle = 360
      }
    }
  }
}

/// ゲット演出で上から落ちてくる紙吹雪。
private struct QuizConfetti: View {
  /// 紙吹雪 1 枚分の落ち方。
  private struct Piece: Identifiable {
    let id: Int
    let horizontalRatio: Double
    let delay: Double
    let duration: Double
    let rotation: Double
    let width: Double
    let height: Double
    let color: Color
  }

  private let pieces: [Piece] = (0..<46).map { index in
    Piece(
      id: index,
      horizontalRatio: Double.random(in: 0.02...0.98),
      delay: Double.random(in: 0...1.6),
      duration: Double.random(in: 1.8...3.4),
      rotation: Double.random(in: 240...900),
      width: Double.random(in: 6...12),
      height: Double.random(in: 10...18),
      color: QuizColor.confetti[index % QuizColor.confetti.count]
    )
  }

  @State private var falling = false

  var body: some View {
    GeometryReader { proxy in
      ForEach(pieces) { piece in
        Rectangle()
          .fill(piece.color)
          .frame(width: piece.width, height: piece.height)
          .rotationEffect(.degrees(falling ? piece.rotation : 0))
          .position(
            x: piece.horizontalRatio * proxy.size.width,
            y: falling ? proxy.size.height + 40 : -40
          )
          .animation(
            .linear(duration: piece.duration).delay(piece.delay).repeatForever(autoreverses: false),
            value: falling
          )
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .onAppear { falling = true }
  }
}

extension Color {
  /// デザイントークンの 16 進数表記から色を作る。
  fileprivate init(hexadecimal: UInt32) {
    self.init(
      red: Double((hexadecimal >> 16) & 0xFF) / 255,
      green: Double((hexadecimal >> 8) & 0xFF) / 255,
      blue: Double(hexadecimal & 0xFF) / 255
    )
  }
}

extension View {
  /// 同じ形を真下へずらして重ねる、ぼかさないべた影。
  fileprivate func quizSolidShadow(cornerRadius: CGFloat, offset: CGFloat) -> some View {
    background(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(QuizColor.ink)
        .offset(y: offset)
    )
  }
}

#Preview("ゲット演出") {
  QuizGetOverlay(
    result: QuizResult(
      pokemon: Pokemon(
        id: 1,
        japaneseName: "テストモン",
        spriteURL: URL(string: "https://example.com/1.png")!
      ),
      isNewCatch: true
    ),
    imageCache: nil,
    onNext: {}
  )
}

#Preview("よみこみちゅう") {
  ZStack {
    QuizColor.background.ignoresSafeArea()
    QuizStatusView<ProgressView, EmptyView>(text: QuizText.loading) { ProgressView() }
  }
}
