import Foundation

/// 画像データを URL から取得する処理を抽象化する。
protocol HTTPDataLoading: Sendable {
  func data(from url: URL) async throws -> (Data, URLResponse)
}

/// URLSession を使って画像データを取得する。
struct URLSessionDataLoader: HTTPDataLoading {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func data(from url: URL) async throws -> (Data, URLResponse) {
    try await session.data(from: url)
  }
}

/// スプライト画像を Caches ディレクトリへ保存し、同じ画像の再取得を避ける。
actor PokemonImageCache {
  private let fileManager: FileManager
  private let cacheDirectory: URL
  private let dataLoader: any HTTPDataLoading

  init(
    fileManager: FileManager = .default,
    cacheDirectory: URL? = nil,
    dataLoader: any HTTPDataLoading = URLSessionDataLoader()
  ) throws {
    self.fileManager = fileManager
    self.dataLoader = dataLoader

    if let cacheDirectory {
      self.cacheDirectory = cacheDirectory
    } else {
      guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        throw PokemonImageCacheError.cachesDirectoryNotFound
      }
      self.cacheDirectory = cachesDirectory.appendingPathComponent("PokemonSprites", isDirectory: true)
    }
  }

  func imageData(for pokemon: Pokemon) async throws -> Data {
    let fileURL = cacheDirectory.appendingPathComponent("\(pokemon.id).sprite")
    if fileManager.fileExists(atPath: fileURL.path) {
      return try Data(contentsOf: fileURL)
    }

    let (data, response) = try await dataLoader.data(from: pokemon.spriteURL)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw PokemonImageCacheError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw PokemonImageCacheError.httpStatus(httpResponse.statusCode)
    }

    try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
    return data
  }
}

/// スプライト画像のキャッシュ処理に失敗した理由を表す。
enum PokemonImageCacheError: Error, Equatable {
  case cachesDirectoryNotFound
  case invalidResponse
  case httpStatus(Int)
}
