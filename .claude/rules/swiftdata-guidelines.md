---
paths:
  - "Kanamon/**/*.swift"
---

# SwiftData ガイドライン

kanamon における SwiftData の使用方針。取り込み元: bannzai/mementomorning の同名ルール (Focus リポジトリで実証済みのノウハウが基)。
DB はローカルの SwiftData のみ (サーバー DB なし。documents/adr/0002-local-only-infra.md 参照)。保存するのはゲット状況 (図鑑の進捗) 等の進捗データのみで、ポケモンのマスタデータは保存せず PokeAPI からのキャッシュで扱う (.claude/rules/pokemon-assets-no-commit.md 参照)。

## 1. PersistenceController パターン

永続化層は `@MainActor struct PersistenceController` のシングルトンで管理する。

- 新しいモデルを追加したら `static let types: [any PersistentModel.Type]` にも追加する (Schema はここから構築される)
- テスト / Preview 環境では `isStoredInMemoryOnly: true` でメモリ内 DB を使う

## 2. @Model 定義の慣習

- `@Model final class` で宣言し、`@Attribute(.unique) var id: UUID` で一意な ID を持たせる
- `createdDateTime` はデフォルト値 `Date.now` で宣言する
- 更新は `private(set)` + ドメインメソッド経由で行い `updatedDateTime` を更新する (`.claude/rules/coding-rules-entity.md` が SSOT)

## 3. マイグレーション戦略

軽量マイグレーションに頼る。`VersionedSchema` / `SchemaMigrationPlan` は使わない。

- 新規プロパティは「プリミティブ型の Optional」で追加する (SwiftData の自動軽量マイグレーションが適用される)
- 独自の Codable オブジェクトをプロパティとして保存しない (マイグレーションが困難になるため)
- 非 Optional のプリミティブ型を新規追加しない (既存データが nil でクラッシュする)

## 4. クエリ

- 時間経過で蓄積するモデルの `@Query` / `FetchDescriptor` には `fetchLimit` を設定する
- ユーザーの入力に応じてクエリ内容が変わる場合は `@Query` ではなく `FetchDescriptor` を使う View ラッパーで対応する (`@Query` は初期化時に条件が固定される)

## 5. Preview での SwiftData

- `PersistenceController` から作った `ModelContext` にテストデータを `insert()` → `try! save()` して、View に `.modelContainer(container)` を付ける
- Preview のサンプルデータに実在のポケモン名・画像を使わない (架空の名前を使う。pokemon-assets-no-commit.md 参照)
