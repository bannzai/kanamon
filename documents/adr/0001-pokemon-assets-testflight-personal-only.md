# 0001. ポケモン素材を使うため配布は TestFlight の個人利用に限定し、素材はリポジトリに commit しない

## Status
Accepted (2026-08-25)

## Context

kanamon はポケモンの名前・スプライト画像を読み練習の素材にする (企画: https://github.com/bannzai/IdeaMemo/issues/189 )。素材の権利を調査した結果:

- PokeAPI のスプライトは「All image contents within are Copyright The Pokémon Company.」と明記されている ( https://github.com/PokeAPI/sprites/blob/master/LICENCE.txt )。PokeAPI 自体のオープンソースライセンスは API ソフトウェアのものであり、画像・名称の著作権・商標 (任天堂 / The Pokémon Company) を上書きしない
- ポケモン公式のファン利用条項は「個人的・非商業的な家庭内利用 (personal, noncommercial home use)」に限定している ( https://www.pokemon.com/us/legal/information )
- App Store 審査ガイドライン 5.2.1 / Google Play ポリシーは第三者 IP の無断使用を禁止しており、任天堂・ポケモン社はファン制作物への権利行使 (DMCA・削除要求) に積極的

## Decision

- **配布は TestFlight のみの個人利用** (自分の子ども向け)。App Store / Google Play には公開しない
- **リポジトリは public のまま、ポケモンの画像・データファイルを commit しない**。public リポジトリへの画像 commit は「家庭内利用」を超えた公衆への再配布に当たるため
- アプリは実行時に PokeAPI から日本語名・スプライトを取得し、端末内にのみキャッシュする。アプリバイナリにも画像を同梱しない
- 素材の扱いのルール化は `.claude/rules/pokemon-assets-no-commit.md` で行う

## Consequences

**良い点:**
- 公式ファン条項の範囲内に収まり、権利リスクを取らずにポケモンの動機付け効果 (図鑑で集めたくなる・好きなキャラの名前を読みたい) を使える
- コードは public に置けるので、通常のワークフロー (public リポジトリの無料 CI 等) が使える

**悪い点 / 引き受けるリスク:**
- ストア公開・収益化の道はこの企画のままでは存在しない。公開したくなったらオリジナル素材 (または CC0 素材) への全面差し替えが必要で、その時は別 ADR で決め直す
- 初回起動にネットワークが必要 (キャッシュ後はオフラインで動作)
- PokeAPI の可用性・フェアユースポリシーに依存する (キャッシュで呼び出し回数を最小化する)
