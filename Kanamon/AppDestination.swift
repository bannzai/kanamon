import Foundation

/// ホームから遷移できるアプリ内の画面。ホーム画面の導線と NavigationStack の遷移先を表す。
///
/// 表示用の文言・記号・色は持たせず (`.claude/rules/coding-rules-entity.md`)、
/// 画面側 (`HomeMenuItem`) の switch で組み立てる。
enum AppDestination: String, CaseIterable, Hashable, Identifiable {
  /// ポケモンの一覧とゲット状況を見る画面。
  case zukan
  /// 名前を大きく表示して読み方を練習する画面。
  case yomiRenshu
  /// 絵に対して名前を 4 択で答える画面。
  case quiz

  var id: String { rawValue }
}

/// ずかんのセルからよみれんしゅうへ進む時の遷移値。どの 1 匹を開くかをポケモン ID で持つ。
///
/// `AppDestination` はホームの導線として `CaseIterable` を保つ必要があるため、関連値を持つ遷移はこちらに分ける。
struct YomiRenshuDestination: Hashable {
  let pokemonID: Int
}
