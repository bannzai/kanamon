import Foundation
import SwiftData

/// ずかんでゲット済みになったポケモンを表す。
/// ゲットした事実と日時だけを端末内に保存し、名前やスプライトなどのマスタデータは持たない。
/// ゲット済みを取り消す仕様がないため更新用のドメインメソッドを持たず、`updatedDateTime` も宣言しない。
@Model
final class CaughtPokemon {
  @Attribute(.unique) private(set) var pokemonID: Int
  private(set) var createdDateTime: Date = Date.now

  init(pokemonID: Int, createdDateTime: Date = .now) {
    self.pokemonID = pokemonID
    self.createdDateTime = createdDateTime
  }
}

/// ゲット状況を SwiftData へ保存し、ずかんへ読み出す。
@MainActor
final class CaughtPokemonStore {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  /// 保存済みのゲット済みポケモンの ID を返す。
  func caughtPokemonIDs() throws -> Set<Int> {
    let descriptor = FetchDescriptor<CaughtPokemon>()
    return Set(try modelContext.fetch(descriptor).map(\.pokemonID))
  }

  /// ポケモンをゲット済みにする。すでにゲット済みなら何もしないため、繰り返し呼んでも結果は変わらない。
  func markCaught(pokemonID: Int) throws {
    var descriptor = FetchDescriptor<CaughtPokemon>(
      predicate: #Predicate { $0.pokemonID == pokemonID }
    )
    descriptor.fetchLimit = 1
    guard try modelContext.fetch(descriptor).isEmpty else {
      return
    }

    modelContext.insert(CaughtPokemon(pokemonID: pokemonID))
    try modelContext.save()
  }

  #if DEBUG
    /// 保存済みのゲット状況をすべて消す。開発者メニューから未ゲットの見た目を確認するために使う。
    func removeAllCaught() throws {
      try modelContext.delete(model: CaughtPokemon.self)
      try modelContext.save()
    }
  #endif
}
