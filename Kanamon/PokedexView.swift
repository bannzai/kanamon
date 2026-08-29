import SwiftUI
import UIKit

/// ずかん画面で表示する文言。子どもが読めるようにひらがな・カタカナだけで書く。
enum PokedexText {
  static let title = "ずかん"
  static let caughtCountLabel = "ゲット した かず"
  static let loading = "よみこみちゅう"
  static let failed = "よみこめなかったよ"
  static let retry = "もういちど"
  static let unknownName = "？？？"
  static let lockedToast = "クイズ で あてると ここ に とうろく されるよ"
}

/// ずかん画面。赤い図鑑デバイスにはめ込まれた画面の中に、ポケモンのグリッド一覧とゲット状況・進捗を表示する。
struct PokedexView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var model: PokedexModel?
  /// 「もういちど」で増やし、`.task(id:)` に読み込みをやり直させる。画面が消えれば読み込みごとキャンセルされる
  @State private var loadRequestCount = 0

  var body: some View {
    Group {
      if let model {
        PokedexContentView(model: model) {
          loadRequestCount += 1
        }
      } else {
        ProgressView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // NavigationStack は自前の地の色 (白) を敷くため、画面ごとにクリームを塗り直す
    .background(DesignColor.cream)
    .toolbar(.hidden, for: .navigationBar)
    .navigationDestination(for: YomiRenshuDestination.self) { destination in
      YomiRenshuView(initialPokemonID: destination.pokemonID)
    }
    .task(id: loadRequestCount) {
      let model = self.model ?? PokedexModel(modelContext: modelContext)
      self.model = model

      if model.state != .loaded {
        await model.load()
      }
    }
  }
}

/// 読み込み済みのモデルを受け取り、ずかんの見出し・進捗・一覧を描画する。
private struct PokedexContentView: View {
  let model: PokedexModel
  let retryAction: () -> Void

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
      PokedexBackButton { dismiss() }

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
        Button(PokedexText.retry, action: retryAction)
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
        NavigationLink(value: YomiRenshuDestination(pokemonID: pokemon.id)) {
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

  /// 再試行の間隔の上限 (秒)。通信障害が長引いても、復旧後この時間以内には取り直す。
  /// 回数で打ち切るとその後に通信が復旧しても空欄のままになるため、セルが表示されている間は取れるまで続ける
  /// (`.task` はセルが画面から消えると SwiftUI がキャンセルする)
  private static let maximumRetryIntervalSeconds = 30

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
      // 別のポケモンに変わった時に前のポケモンの画像が残らないよう、読み込みの前に消す
      spriteImage = nil
      await loadSprite()
    }
  }

  private func loadSprite() async {
    guard let imageCache else {
      return
    }

    // 取得を待つ間に別のポケモンへ切り替わったことを、取得結果を出す前に見分けるために控えておく
    let requestedPokemonID = pokemon.id
    var retryIntervalSeconds = 1
    while !Task.isCancelled {
      if let data = try? await imageCache.imageData(for: pokemon),
        let image = UIImage(data: data)
      {
        // 取得を待つ間に別のポケモンへ切り替わっていたら、前のポケモンの画像を出さずに終わる
        if Task.isCancelled || pokemon.id != requestedPokemonID {
          return
        }

        spriteImage = image
        return
      }

      // 通信の復旧を待つため、失敗するたびに間隔を倍にする (1・2・4・… 最大 30 秒)
      guard (try? await Task.sleep(for: .seconds(retryIntervalSeconds))) != nil else {
        return
      }
      retryIntervalSeconds = min(retryIntervalSeconds * 2, Self.maximumRetryIntervalSeconds)
    }
  }
}

#Preview {
  let pokemons = [
    Pokemon(id: 1, japaneseName: "テストモン", spriteURL: URL(string: "https://example.com/1.png")!),
    Pokemon(id: 2, japaneseName: "サンプルン", spriteURL: URL(string: "https://example.com/2.png")!),
  ]

  return PokedexDeviceFrame {
    NavigationStack {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 10)], spacing: 10) {
        PokedexCell(pokemon: pokemons[0], isCaught: true, imageCache: nil) {}
        PokedexCell(pokemon: pokemons[1], isCaught: false, imageCache: nil) {}
      }
      .padding(20)
    }
  }
}
