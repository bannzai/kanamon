import SwiftUI

/// ポケモンのスプライト画像を `PokemonImageCache` 経由で表示する。
///
/// 画像は実行時に PokeAPI から取得して端末内にだけ置く (`.claude/rules/pokemon-assets-no-commit.md`)。
struct PokemonSpriteImage: View {
  let pokemon: Pokemon

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else {
        // 取得できるまでは形だけ確保して、名前の位置がずれないようにする。
        Color.clear
      }
    }
    .task(id: pokemon.id) {
      image = nil
      image = await Self.loadImage(for: pokemon)
    }
  }

  private static func loadImage(for pokemon: Pokemon) async -> UIImage? {
    guard let cache = try? PokemonImageCache() else {
      return nil
    }
    guard let data = try? await cache.imageData(for: pokemon) else {
      return nil
    }

    return UIImage(data: data)
  }
}
