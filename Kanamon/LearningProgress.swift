import Foundation
import SwiftData

/// ずかんへ登録済みのポケモンを表す永続データ。
@Model
final class CaughtPokemonEntry {
  @Attribute(.unique) private(set) var pokemonID: Int

  init(pokemonID: Int) {
    self.pokemonID = pokemonID
  }
}

/// 五十音の基底文字ごとに、読む・書くの進捗を保持する永続データ。
@Model
final class CharacterProgressEntry {
  @Attribute(.unique) private(set) var normalizedCharacter: String
  private(set) var hasRead: Bool
  private(set) var hasWritten: Bool

  init(normalizedCharacter: Character, hasRead: Bool = false, hasWritten: Bool = false) {
    self.normalizedCharacter = String(normalizedCharacter)
    self.hasRead = hasRead
    self.hasWritten = hasWritten
  }

  func markRead() {
    hasRead = true
  }

  func markWritten() {
    hasWritten = true
  }
}

/// 学習進捗を文字単位で追記し、別のポケモンでも再利用できる形で読み出す。
@MainActor
final class LearningProgressStore {
  private let modelContext: ModelContext

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  func caughtPokemonIDs() throws -> Set<Int> {
    Set(try modelContext.fetch(FetchDescriptor<CaughtPokemonEntry>()).map(\.pokemonID))
  }

  func readCharacters() throws -> Set<Character> {
    try characters(matching: \CharacterProgressEntry.hasRead)
  }

  func writtenCharacters() throws -> Set<Character> {
    try characters(matching: \CharacterProgressEntry.hasWritten)
  }

  func markPokemonCaught(id: Int) throws {
    var descriptor = FetchDescriptor<CaughtPokemonEntry>(
      predicate: #Predicate { $0.pokemonID == id }
    )
    descriptor.fetchLimit = 1
    if try modelContext.fetch(descriptor).isEmpty {
      modelContext.insert(CaughtPokemonEntry(pokemonID: id))
    }

    if modelContext.hasChanges {
      try modelContext.save()
    }
  }

  func markRead(character: Character) throws {
    let entry = try progressEntry(for: character)
    if !entry.hasRead {
      entry.markRead()
    }

    if modelContext.hasChanges {
      try modelContext.save()
    }
  }

  func markWritten(character: Character) throws {
    let entry = try progressEntry(for: character)
    if !entry.hasWritten {
      entry.markWritten()
    }

    if modelContext.hasChanges {
      try modelContext.save()
    }
  }

  private func progressEntry(for character: Character) throws -> CharacterProgressEntry {
    let normalizedCharacter = KatakanaCharacterNormalizer.baseCharacter(from: character)
    let key = String(normalizedCharacter)
    var descriptor = FetchDescriptor<CharacterProgressEntry>(
      predicate: #Predicate { $0.normalizedCharacter == key }
    )
    descriptor.fetchLimit = 1

    if let entry = try modelContext.fetch(descriptor).first {
      return entry
    }

    let entry = CharacterProgressEntry(normalizedCharacter: normalizedCharacter)
    modelContext.insert(entry)
    return entry
  }

  private func characters(
    matching keyPath: KeyPath<CharacterProgressEntry, Bool>
  ) throws -> Set<Character> {
    Set(
      try modelContext.fetch(FetchDescriptor<CharacterProgressEntry>())
        .filter { $0[keyPath: keyPath] }
        .compactMap { $0.normalizedCharacter.first }
    )
  }
}
