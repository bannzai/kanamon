---
paths:
  - "Kanamon/**/*.swift"
---

# コーディングルール (Entity/データ層)

Entity (SwiftData 等) やデータ層に関するコーディングルール。取り込み元: bannzai/mementomorning の同名ルール。

## ドキュメントコメント

- struct, class, enum の宣言直前に `///` のドキュメントコメントを書き、そのデータ型が何を表し、どう使われるかを説明する

## 命名規則

- 変数名には通常、動詞 (editing, selected 等) をつけない。Feature 名が役割を表すため名詞だけでよい。必要な場合はコメントで理由を明記する
- `@AppStorage` の変数名は key 名と一致させる (どの UserDefaults キーを使っているか一目で分かるようにするため)

## プロパティ設計

- enum やフラグで使うプロパティが変わる場合、保存側で「使わない方を nil にする」処理は不要。そのまま保存し、使用側で enum / flag を switch して適切なプロパティを使う。使用方法はコメントで明記する
- SwiftData `@Model` エンティティで外部から更新されるプロパティは `private(set)` にし、ドメインメソッド (セッター) 経由で更新する。ドメインメソッド内で必ず `updatedDateTime = .now` を更新する (SwiftData には CoreData の `willSave` のようなモデルレベルのフックが無いため)。`updatedDateTime` は `private(set) var updatedDateTime: Date = Date.now` として宣言する
- `onChange(of:)` 等でエンティティの変更を検知する場合は、個別プロパティではなく `updatedDateTime` を監視する
- enum に `var label: String` / `var systemImage: String` のような表示用プロパティを持たせない。enum は純粋なデータ型にし、表示ロジックは使用側 (View) の switch で判定する
