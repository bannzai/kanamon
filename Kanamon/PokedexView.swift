import SwiftUI
import UIKit

/// ずかん画面で表示する文言。子どもが読めるようにひらがな・カタカナだけで書く。
enum PokedexText {
  static let title = "ずかん"
  static let deviceTitle = "カナモン"
  static let caughtCountLabel = "ゲット した かず"
  static let loading = "よみこみちゅう"
  static let failed = "よみこめなかったよ"
  static let retry = "もういちど"
  static let back = "もどる"
  static let unknownName = "？？？"
  static let lockedToast = "クイズ で あてると ここ に とうろく されるよ"
}

/// ずかん画面。赤い図鑑デバイスにはめ込まれた画面の中に、ポケモンのグリッド一覧とゲット状況・進捗を表示する。
struct PokedexView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var model: PokedexModel?

  var body: some View {
    PokedexDeviceFrame {
      if let model {
        PokedexContentView(model: model)
      } else {
        ProgressView()
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .task {
      let model = self.model ?? PokedexModel(modelContext: modelContext)
      self.model = model

      if model.state != .loaded {
        await model.load()
      }
    }
  }
}

/// ずかん画面のレイアウト定数。generic な View に static を置けないためここに持つ。
enum PokedexLayout {
  /// 画面の中身の最大幅。iPad では横に引き伸ばさず中央寄せにする (README「7. iPad での拡大方針」)
  static let maximumScreenWidth: CGFloat = 520
}

/// 赤い図鑑デバイスの筐体。左上にレンズと 3 つのランプを置き、その下の画面をはめ込む。
struct PokedexDeviceFrame<Screen: View>: View {
  @ViewBuilder let screen: () -> Screen

  var body: some View {
    ZStack {
      LinearGradient(
        stops: [
          .init(color: DesignColor.redLight, location: 0),
          .init(color: DesignColor.red, location: 0.26),
          .init(color: DesignColor.redDark, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      VStack(spacing: 0) {
        deviceTop
          .padding(.horizontal, 20)
          .padding(.top, 8)
          .padding(.bottom, 10)

        Rectangle()
          .fill(Color.black.opacity(0.16))
          .frame(height: 4)
          .padding(.horizontal, 18)
          .padding(.bottom, 8)

        screen()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(DesignColor.cream)
          .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .strokeBorder(DesignColor.screenInset, lineWidth: 4)
              .padding(6)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .strokeBorder(DesignColor.ink, lineWidth: 6)
          )
          .padding(.horizontal, 12)
          .padding(.bottom, 12)
      }
      .frame(maxWidth: PokedexLayout.maximumScreenWidth)
    }
  }

  private var deviceTop: some View {
    HStack(spacing: 10) {
      PokedexLens()
      PokedexLamp(color: DesignColor.lampRed, blinks: true)
      PokedexLamp(color: DesignColor.yellow, blinks: false)
      PokedexLamp(color: DesignColor.green, blinks: false)
      Spacer()
      Text(PokedexText.deviceTitle)
        .font(.system(size: 19, weight: .black, design: .rounded))
        .kerning(1.5)
        .foregroundStyle(.white)
        .shadow(color: DesignColor.ink, radius: 0, x: 2, y: 0)
        .shadow(color: DesignColor.ink, radius: 0, x: -2, y: 0)
        .shadow(color: DesignColor.ink, radius: 0, x: 0, y: 2)
        .shadow(color: DesignColor.ink, radius: 0, x: 0, y: -2)
    }
    .frame(height: 44)
  }
}

/// 筐体左上の青い円形レンズ。ハイライトを 1 つ乗せる。
private struct PokedexLens: View {
  var body: some View {
    Circle()
      .fill(
        RadialGradient(
          stops: [
            .init(color: DesignColor.lensLight, location: 0),
            .init(color: DesignColor.lensMiddle, location: 0.42),
            .init(color: DesignColor.lensDark, location: 1),
          ],
          center: UnitPoint(x: 0.32, y: 0.28),
          startRadius: 0,
          endRadius: 24
        )
      )
      .overlay(Circle().strokeBorder(DesignColor.lensRing, lineWidth: 4).padding(5))
      .overlay(Circle().strokeBorder(DesignColor.ink, lineWidth: 5))
      .overlay(alignment: .topLeading) {
        Ellipse()
          .fill(Color.white.opacity(0.92))
          .frame(width: 14, height: 9)
          .rotationEffect(.degrees(-24))
          .offset(x: 10, y: 8)
      }
      .frame(width: 44, height: 44)
  }
}

/// 筐体のランプ。赤だけが点滅する。
private struct PokedexLamp: View {
  let color: Color
  let blinks: Bool

  /// 点滅の周期 (README: 1.1 秒で 60% 点灯 / 40% 減光)。TimelineView で明滅を切り替える
  private static let blinkInterval: TimeInterval = 0.55

  var body: some View {
    TimelineView(.periodic(from: .now, by: Self.blinkInterval)) { context in
      let phase = Int(context.date.timeIntervalSinceReferenceDate / Self.blinkInterval) % 2
      Circle()
        .fill(color)
        .overlay(Circle().strokeBorder(DesignColor.ink, lineWidth: 3))
        .frame(width: 15, height: 15)
        .brightness(blinks && phase == 1 ? -0.45 : 0)
    }
  }
}

/// 読み込み済みのモデルを受け取り、ずかんの見出し・進捗・一覧を描画する。
private struct PokedexContentView: View {
  let model: PokedexModel

  @Environment(\.dismiss) private var dismiss
  @State private var toastText: String?

  /// セル幅を保ったまま列数を増やす (iPhone で 3 列・iPad で 5〜6 列)。
  /// 筐体と画面枠のぶん幅が狭いため、README の 110〜130pt より下限を下げて iPhone でも 3 列に収める
  private let columns = [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 10)]

  var body: some View {
    VStack(spacing: 14) {
      header
      progressCard

      if !model.pokemons.isEmpty {
        grid
      } else if model.state == .failed {
        message(PokedexText.failed, showsRetry: true)
      } else {
        message(PokedexText.loading, showsRetry: false)
      }
    }
    .padding(20)
    .overlay(alignment: .bottom) {
      if let toastText {
        PokedexToast(text: toastText)
          .padding(.horizontal, 20)
          .padding(.bottom, 24)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: 0.3), value: toastText)
    .task(id: toastText) {
      guard toastText != nil else {
        return
      }
      // プロトタイプと同じ 2.2 秒で消す
      try? await Task.sleep(for: .seconds(2.2))
      toastText = nil
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 26, weight: .black))
          .foregroundStyle(DesignColor.ink)
          .frame(width: 60, height: 60)
          .background(DesignColor.paper)
          .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DesignColor.ink, lineWidth: 5))
          .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .fill(DesignColor.ink)
              .offset(y: 5)
          )
      }
      .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
      .accessibilityLabel(PokedexText.back)

      Text(PokedexText.title)
        .font(.system(size: 30, weight: .black, design: .rounded))
        .foregroundStyle(DesignColor.ink)
        .lineLimit(1)
        .fixedSize()
        .layoutPriority(1)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(model.numberRangeText)
        .font(.system(size: 16, weight: .black, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(DesignColor.ink)
        .padding(.horizontal, 11)
        .frame(height: 40)
        .background(DesignColor.yellow)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(DesignColor.ink, lineWidth: 4))
        .background(
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(DesignColor.ink)
            .offset(y: 4)
        )

      #if DEBUG
        NavigationLink {
          DebugMenuView(model: model)
        } label: {
          Image(systemName: "wrench.fill")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(DesignColor.ink.opacity(0.6))
            .frame(width: 24, height: 32)
        }
        .accessibilityIdentifier("debug_menu_link")
      #endif
    }
    .frame(height: 64)
  }

  private var progressCard: some View {
    VStack(spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(PokedexText.caughtCountLabel)
          .font(.system(size: 17, weight: .black, design: .rounded))
          .foregroundStyle(DesignColor.ink)
        Spacer()
        Text(model.progressText)
          .font(.system(size: 23, weight: .black, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(DesignColor.red)
      }

      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          DesignColor.cream
          DesignColor.green
            .frame(width: geometry.size.width * model.progressFraction)
        }
      }
      .frame(height: 22)
      .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(DesignColor.ink, lineWidth: 4))
      .animation(.easeOut(duration: 0.5), value: model.progressFraction)
    }
    .padding(.horizontal, 14)
    .padding(.top, 12)
    .padding(.bottom, 14)
    .background(DesignColor.paper)
    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(DesignColor.ink, lineWidth: 5))
    .background(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .fill(DesignColor.ink)
        .offset(y: 8)
    )
    .padding(.bottom, 8)
  }

  private var grid: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 10) {
        ForEach(model.pokemons, id: \.id) { pokemon in
          PokedexCell(
            pokemon: pokemon,
            isCaught: model.isCaught(pokemon),
            imageCache: model.imageCache
          ) {
            toastText = PokedexText.lockedToast
          }
        }
      }
      .padding(.bottom, 8)
    }
  }

  private func message(_ text: String, showsRetry: Bool) -> some View {
    VStack(spacing: 16) {
      Spacer()
      Text(text)
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .foregroundStyle(DesignColor.ink)

      if showsRetry {
        Button(PokedexText.retry) {
          Task { await model.load() }
        }
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .foregroundStyle(DesignColor.blue)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

/// ずかんの 1 マス。ゲット済みは白地にカラーのアートワークと名前、未ゲットは砂色の地にシルエットと伏せ字を表示する。
/// ゲット済みをタップするとよみれんしゅうへ進み、未ゲットをタップすると `lockedTapAction` を呼ぶ。
struct PokedexCell: View {
  let pokemon: Pokemon
  let isCaught: Bool
  let imageCache: PokemonImageCache?
  let lockedTapAction: () -> Void

  var body: some View {
    Group {
      if isCaught {
        NavigationLink(value: AppDestination.yomiRenshu) {
          label
        }
      } else {
        Button(action: lockedTapAction) {
          label
        }
      }
    }
    .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
  }

  private var label: some View {
    VStack(spacing: 2) {
      Spacer(minLength: 0)
      PokemonSpriteView(pokemon: pokemon, isCaught: isCaught, imageCache: imageCache)
        .frame(width: 74, height: 74)
      Text(isCaught ? pokemon.japaneseName : PokedexText.unknownName)
        .font(.system(size: 14, weight: .black, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(isCaught ? DesignColor.ink : DesignColor.sandDark)
    }
    .padding(.top, 6)
    .padding(.horizontal, 4)
    .padding(.bottom, 4)
    .frame(maxWidth: .infinity)
    .frame(height: 128)
    .overlay(alignment: .topLeading) {
      Text(pokedexNumberText(id: pokemon.id))
        .font(.system(size: 11, weight: .black, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(DesignColor.ink.opacity(0.55))
        .padding(.top, 4)
        .padding(.leading, 6)
    }
    .background(isCaught ? DesignColor.paper : DesignColor.sand)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(isCaught ? DesignColor.ink : DesignColor.sandBorder, lineWidth: 4)
    )
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(isCaught ? DesignColor.ink : DesignColor.sandBorder)
        .offset(y: 5)
    )
  }
}

/// 押下で 5px 沈んで影が消える、確定デザインのボタン挙動。
struct PokedexPressButtonStyle: ButtonStyle {
  let pressOffset: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .offset(y: configuration.isPressed ? pressOffset : 0)
  }
}

/// 画面下に出る短い通知。インクの地に白文字で表示し、時間で消える。
struct PokedexToast: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 16, weight: .bold, design: .rounded))
      .foregroundStyle(.white)
      .multilineTextAlignment(.leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(DesignColor.ink)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

/// アートワークをキャッシュ経由で読み込み、ゲット状況に応じてカラー / インク色のシルエットで描画する。
struct PokemonSpriteView: View {
  let pokemon: Pokemon
  let isCaught: Bool
  let imageCache: PokemonImageCache?

  @State private var spriteImage: UIImage?

  /// スプライト取得をあきらめるまでの試行回数。
  /// 一時的な通信障害で 1 回失敗しただけのセルが、次にセルが作り直されるまで空欄のまま残るのを防ぐ
  private static let maximumAttempts = 5

  /// 未ゲットのシルエットの濃さ (README: `brightness(0) opacity(.34)`)
  private static let silhouetteOpacity = 0.34

  var body: some View {
    Group {
      if let spriteImage {
        Image(uiImage: spriteImage)
          .renderingMode(isCaught ? .original : .template)
          .resizable()
          .scaledToFit()
          .foregroundStyle(DesignColor.ink.opacity(Self.silhouetteOpacity))
      } else {
        Color.clear
      }
    }
    .task(id: pokemon.id) {
      await loadSprite()
    }
  }

  private func loadSprite() async {
    guard let imageCache else {
      return
    }

    for attempt in 0..<Self.maximumAttempts {
      if attempt > 0 {
        // 通信の復旧を待つため、失敗するたびに間隔を倍にする (1・2・4・8 秒)
        try? await Task.sleep(for: .seconds(1 << (attempt - 1)))
      }
      if Task.isCancelled {
        return
      }

      if let data = try? await imageCache.imageData(for: pokemon),
        let image = UIImage(data: data)
      {
        spriteImage = image
        return
      }
    }
  }
}

#Preview {
  let pokemons = [
    Pokemon(id: 1, japaneseName: "テストモン", spriteURL: URL(string: "https://example.com/1.png")!),
    Pokemon(id: 2, japaneseName: "サンプルン", spriteURL: URL(string: "https://example.com/2.png")!),
  ]

  return NavigationStack {
    PokedexDeviceFrame {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 10)], spacing: 10) {
        PokedexCell(pokemon: pokemons[0], isCaught: true, imageCache: nil) {}
        PokedexCell(pokemon: pokemons[1], isCaught: false, imageCache: nil) {}
      }
      .padding(20)
    }
  }
}
