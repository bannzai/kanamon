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
  /// 文字タイルを並べて名前を組み立てる画面。
  case nameBuilder

  var id: String { rawValue }
}
