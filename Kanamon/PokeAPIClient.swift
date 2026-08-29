import Foundation

/// PokeAPI REST API から日本語名とスプライト URL を取得する。
struct PokeAPIClient: PokemonDataSource {
  private let session: URLSession
  private let baseURL: URL

  init(
    session: URLSession = .shared,
    baseURL: URL = URL(string: "https://pokeapi.co/api/v2/")!
  ) {
    self.session = session
    self.baseURL = baseURL
  }

  func fetchPokemon(id: Int) async throws -> Pokemon {
    let speciesURL = baseURL.appendingPathComponent("pokemon-species/\(id)")
    let pokemonURL = baseURL.appendingPathComponent("pokemon/\(id)")

    async let speciesResponse: PokemonSpeciesResponse = request(speciesURL)
    async let pokemonResponse: PokemonResponse = request(pokemonURL)
    let (species, pokemon) = try await (speciesResponse, pokemonResponse)

    guard let japaneseName = species.names.first(where: { $0.language.name == "ja" })?.name else {
      throw PokeAPIError.japaneseNameNotFound(id: id)
    }
    guard
      let spriteURLString = pokemon.sprites.frontDefault,
      let spriteURL = URL(string: spriteURLString)
    else {
      throw PokeAPIError.spriteURLNotFound(id: id)
    }

    return Pokemon(id: pokemon.id, japaneseName: japaneseName, spriteURL: spriteURL)
  }

  private func request<Response: Decodable>(_ url: URL) async throws -> Response {
    let (data, response) = try await session.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw PokeAPIError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw PokeAPIError.httpStatus(httpResponse.statusCode)
    }

    return try JSONDecoder().decode(Response.self, from: data)
  }
}

/// PokeAPI からメタデータを取得できなかった理由を表す。
enum PokeAPIError: Error, Equatable {
  case invalidResponse
  case httpStatus(Int)
  case japaneseNameNotFound(id: Int)
  case spriteURLNotFound(id: Int)
}

/// pokemon-species エンドポイントで返される名称一覧を表す。
private struct PokemonSpeciesResponse: Decodable {
  let names: [LocalizedName]
}

/// 言語情報付きの名称を表す。
private struct LocalizedName: Decodable {
  let name: String
  let language: APIResource
}

/// PokeAPI の別リソースへの参照を表す。
private struct APIResource: Decodable {
  let name: String
}

/// pokemon エンドポイントで返される ID とスプライト情報を表す。
private struct PokemonResponse: Decodable {
  let id: Int
  let sprites: Sprites
}

/// 利用する正面スプライトの URL を表す。
private struct Sprites: Decodable {
  let frontDefault: String?

  enum CodingKeys: String, CodingKey {
    case frontDefault = "front_default"
  }
}
