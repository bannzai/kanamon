import Foundation

/// KanjiVG の SVG を実行時に取得し、端末の Caches ディレクトリへ保存する。
actor KanjiVGCache {
  private let fileManager: FileManager
  private let cacheDirectory: URL
  private let dataLoader: any HTTPDataLoading
  private let baseURL: URL
  private var downloadTasks: [String: Task<Data, Error>] = [:]

  init(
    fileManager: FileManager = .default,
    cacheDirectory: URL? = nil,
    dataLoader: any HTTPDataLoading = URLSessionDataLoader(),
    baseURL: URL = URL(
      string: "https://raw.githubusercontent.com/KanjiVG/kanjivg/master/kanji/"
    )!
  ) throws {
    self.fileManager = fileManager
    self.dataLoader = dataLoader
    self.baseURL = baseURL

    if let cacheDirectory {
      self.cacheDirectory = cacheDirectory
    } else {
      guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        throw KanjiVGCacheError.cachesDirectoryNotFound
      }
      self.cacheDirectory = cachesDirectory.appendingPathComponent("KanjiVG", isDirectory: true)
    }
  }

  func strokeData(for character: Character) async throws -> Data {
    let fileName = try Self.fileName(for: character)
    let fileURL = cacheDirectory.appendingPathComponent(fileName)
    if fileManager.fileExists(atPath: fileURL.path) {
      return try Data(contentsOf: fileURL)
    }

    if let downloadTask = downloadTasks[fileName] {
      return try await downloadTask.value
    }

    let downloadTask = Task {
      try await downloadAndStore(fileName: fileName, at: fileURL)
    }
    downloadTasks[fileName] = downloadTask
    defer { downloadTasks[fileName] = nil }
    return try await downloadTask.value
  }

  private func downloadAndStore(fileName: String, at fileURL: URL) async throws -> Data {
    let sourceURL = baseURL.appendingPathComponent(fileName)
    let (data, response) = try await dataLoader.data(from: sourceURL)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw KanjiVGCacheError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw KanjiVGCacheError.httpStatus(httpResponse.statusCode)
    }

    try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
    return data
  }

  private static func fileName(for character: Character) throws -> String {
    let scalars = String(character).precomposedStringWithCanonicalMapping.unicodeScalars
    guard scalars.count == 1, let codePoint = scalars.first, codePoint.value <= 0xFFFFF else {
      throw KanjiVGCacheError.unsupportedCharacter(character)
    }

    return String(format: "%05x.svg", codePoint.value)
  }
}

/// KanjiVG の取得・キャッシュに失敗した理由を表す。
enum KanjiVGCacheError: Error, Equatable {
  case cachesDirectoryNotFound
  case unsupportedCharacter(Character)
  case invalidResponse
  case httpStatus(Int)
}
