import SwiftUI
import UIKit

/// ずかん画面で表示する文言。子どもが読めるようにひらがな・カタカナだけで書く。
enum PokedexText {
  static let title = "ずかん"
  static let loading = "よみこみちゅう"
  static let failed = "よみこめなかったよ"
  static let retry = "もういちど"
  static let unknownName = "？？？"
}

/// ずかん画面で使う色。ライト / ダークどちらでもシルエットが黒く読めるように固定色で持つ。
enum PokedexColor {
  static let background = Color(white: 0.99)
  static let card = Color(white: 0.93)
  static let text = Color(white: 0.12)
  static let silhouette = Color.black
}

/// ずかん画面。ポケモンをグリッドで一覧し、ゲット状況と進捗を表示する。
struct PokedexView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var model: PokedexModel?

  var body: some View {
    NavigationStack {
      ZStack {
        PokedexColor.background.ignoresSafeArea()

        if let model {
          PokedexContentView(model: model)
        } else {
          ProgressView()
        }
      }
      .toolbar(.hidden, for: .navigationBar)
    }
    .task {
      let model = self.model ?? PokedexModel(modelContext: modelContext)
      self.model = model

      if model.state != .loaded {
        await model.load()
      }
    }
  }
}

/// 読み込み済みのモデルを受け取り、ずかんの見出しと一覧を描画する。
private struct PokedexContentView: View {
  let model: PokedexModel

  private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

  var body: some View {
    VStack(spacing: 0) {
      header

      if !model.pokemons.isEmpty {
        grid
      } else if model.state == .failed {
        message(PokedexText.failed, showsRetry: true)
      } else {
        message(PokedexText.loading, showsRetry: false)
      }
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(PokedexText.title)
        .font(.system(size: 34, weight: .heavy))
      Spacer()
      Text(model.progressText)
        .font(.system(size: 24, weight: .heavy))
        .monospacedDigit()

      #if DEBUG
        NavigationLink("デバッグ") {
          DebugMenuView(model: model)
        }
        .font(.system(size: 14, weight: .bold))
        .accessibilityIdentifier("debug_menu_link")
      #endif
    }
    .foregroundStyle(PokedexColor.text)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var grid: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(model.pokemons, id: \.id) { pokemon in
          PokedexCell(
            pokemon: pokemon,
            isCaught: model.isCaught(pokemon),
            imageCache: model.imageCache
          )
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
    }
  }

  private func message(_ text: String, showsRetry: Bool) -> some View {
    VStack(spacing: 16) {
      Spacer()
      Text(text)
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(PokedexColor.text)

      if showsRetry {
        Button(PokedexText.retry) {
          Task { await model.load() }
        }
        .font(.system(size: 22, weight: .bold))
      }

      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

/// ずかんの 1 マス。ゲット済みはカラーのスプライトと名前、未ゲットはシルエットと伏せ字を表示する。
struct PokedexCell: View {
  let pokemon: Pokemon
  let isCaught: Bool
  let imageCache: PokemonImageCache?

  var body: some View {
    VStack(spacing: 6) {
      PokemonSpriteView(pokemon: pokemon, isCaught: isCaught, imageCache: imageCache)
        .frame(height: 80)
      Text(isCaught ? pokemon.japaneseName : PokedexText.unknownName)
        .font(.system(size: 18, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundStyle(PokedexColor.text)
    }
    .padding(8)
    .frame(maxWidth: .infinity)
    .background(RoundedRectangle(cornerRadius: 16).fill(PokedexColor.card))
  }
}

/// スプライト画像をキャッシュ経由で読み込み、ゲット状況に応じてカラー / 黒いシルエットで描画する。
struct PokemonSpriteView: View {
  let pokemon: Pokemon
  let isCaught: Bool
  let imageCache: PokemonImageCache?

  @State private var spriteImage: UIImage?

  var body: some View {
    Group {
      if let spriteImage {
        Image(uiImage: spriteImage)
          .renderingMode(isCaught ? .original : .template)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
          .foregroundStyle(PokedexColor.silhouette)
      } else {
        Color.clear
      }
    }
    .task(id: pokemon.id) {
      guard let imageCache, let data = try? await imageCache.imageData(for: pokemon) else {
        return
      }

      spriteImage = UIImage(data: data)
    }
  }
}

#Preview {
  let pokemons = [
    Pokemon(id: 1, japaneseName: "テストモン", spriteURL: URL(string: "https://example.com/1.png")!),
    Pokemon(id: 2, japaneseName: "サンプルン", spriteURL: URL(string: "https://example.com/2.png")!),
  ]

  return VStack(spacing: 12) {
    PokedexCell(pokemon: pokemons[0], isCaught: true, imageCache: nil)
    PokedexCell(pokemon: pokemons[1], isCaught: false, imageCache: nil)
  }
  .padding()
  .background(PokedexColor.background)
}
