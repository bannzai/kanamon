import SwiftUI

/// 図鑑デバイスの筐体と、全画面で共通に使う部品の文言。
/// 子どもが読めるようにひらがな・カタカナだけで書く。
enum PokedexDeviceText {
  static let title = "カナモン"
  static let back = "もどる"
}

/// 図鑑デバイスのレイアウト定数。generic な View に static を置けないためここに持つ。
enum PokedexLayout {
  /// 画面の中身の最大幅。iPad では横に引き伸ばさず中央寄せにする (README「7. iPad での拡大方針」)
  static let maximumScreenWidth: CGFloat = 520
}

/// 赤い図鑑デバイスの筐体。左上にレンズと 3 つのランプを置き、その下の画面をはめ込む。
///
/// アプリ全体を「赤い図鑑に画面がはめ込まれている」構図にするため
/// (documents/design/README.md「1. デザインの土台」)、画面ごとではなく `ContentView` で
/// `NavigationStack` ごと 1 度だけ包む。こうすると画面遷移の間も筐体が動かず、
/// 新しい画面を足しても筐体の実装を書き足さずに済む。
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
      Text(PokedexDeviceText.title)
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

/// 押下で 5px 沈んで影が消える、確定デザインのボタン挙動。
struct PokedexPressButtonStyle: ButtonStyle {
  let pressOffset: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .offset(y: configuration.isPressed ? pressOffset : 0)
  }
}

/// 確定デザインのカード型ボタン。押している間だけ 5pt 沈み、真下の影が消える
/// (documents/design/README.md「6. スタイルトークン > 形」)。
///
/// 影をラベル側に描くと、`PokedexPressButtonStyle` がラベルごと沈めた時に影も一緒に下がって
/// 隣のカードへ張り出すため、影の描画をボタンの見た目としてここで持つ。
struct PokedexCardButtonStyle: ButtonStyle {
  let background: Color
  let cornerRadius: CGFloat
  let borderWidth: CGFloat
  /// 真下へずらす影の高さ (ぼかさない)
  let shadowHeight: CGFloat

  /// 押し込む深さ。README の「押下: translateY(5px) して影を消す」に合わせる
  private static let pressOffset: CGFloat = 5

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    return configuration.label
      .background(background)
      .clipShape(shape)
      .overlay(shape.strokeBorder(DesignColor.ink, lineWidth: borderWidth))
      .background(shape.fill(DesignColor.ink).offset(y: configuration.isPressed ? 0 : shadowHeight))
      .offset(y: configuration.isPressed ? Self.pressOffset : 0)
  }
}

/// 各画面の左上に置く戻るボタン。白地の角丸枠に矢印を入れる (README「2. 画面一覧と遷移」)。
struct PokedexBackButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "chevron.left")
        .font(.system(size: 26, weight: .black))
        .foregroundStyle(DesignColor.ink)
        .frame(width: 60, height: 60)
        .background(DesignColor.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(DesignColor.ink, lineWidth: 5)
        )
        .background(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(DesignColor.ink)
            .offset(y: 5)
        )
    }
    .buttonStyle(PokedexPressButtonStyle(pressOffset: 5))
    .accessibilityLabel(PokedexDeviceText.back)
  }
}
