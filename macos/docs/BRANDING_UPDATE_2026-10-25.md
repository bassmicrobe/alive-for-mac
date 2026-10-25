# ロゴ・アプリアイコン更新 — 2026-10-25

## 反映内容

提供された `logo-svg.zip` の SVG 10 点を、形・色・余白を変更せず
[`Resources/Branding`](../Resources/Branding/) に追加した。

- [日本語 README](../../.github/README.md) と [英語 README](../../.github/README.en.md)
  の先頭に横長ロゴを追加。`prefers-color-scheme` により明暗版を切り替え、
  画像の代替テキストは `Alive for Mac` とした。
- ダーク版アプリアイコンを 1024 px PNG に変換し、16〜1024 px の全 10 表現を
  収録した `AppIcon.icns` を追加。アプリの「情報」画面もこのアイコンを表示する。
- `build-app.sh` は macOS 専用の ICNS を同梱するよう変更。
  アイコンが欠けている場合はビルド前にエラーを返す。
- 再生成用の `generate-app-icon.sh` と素材の説明を追加。
  通常ビルドの依存は増えていない。ICNS の再生成には macOS 標準ツールを使用する。

実装コミット: `bda5ca8`（README）、`05a3640`（素材・アイコン・ビルド）。
ブランチ: `codex/branding-2026-10-25`。

## 検証結果

| 確認 | 結果 |
| --- | --- |
| ZIP 原本との照合 | SVG 10 点すべてバイト単位で一致 |
| README 画像 | 日英両方の参照先が実在。明暗版をレンダリングして目視確認 |
| ICNS 再展開 | 全 10 表現の寸法が正しいことを確認 |
| スクリプト | `bash -n`、`git diff --check` 成功 |
| アプリビルド | `macos/scripts/build-app.sh --native` 成功 |
| 署名 | アプリと同梱拡張の `codesign --verify --deep --strict` 成功 |
| 同梱アイコン | コミットした ICNS と生成アプリ内の ICNS が完全一致 |
| 実画面 | 独立した検証用アプリの「設定 → 情報」で新アイコンを確認 |
| 独立レビュー | アイコン生成・同梱・README の参照について指摘なし |

ICNS SHA-256:
`c1f34ceabe48f5e259c3115a0c2e5a09daca5c6ff140bfbf460c0d04759cd1f7`

検証用アプリは固有の Bundle ID と `ALIVE_HOME` を使い、合成データで起動した。
Spotlight はテスト用の無処理バックエンドを使用し、拡張機能を検証用コピーから除外。
確認後に検証用アプリを終了した。今回の変更は素材・文書・同梱処理のみのため、
直前の監査で成功した全体テストを重複実行せず、アイコン生成と release ビルドを検証した。

ローカル成果物:

- `macos/build/Alive for Mac.app` — 新アイコンを含むホスト CPU 向けビルド。
- `macos/build/branding-2026-10-25/build.log` — ビルド・署名のログ。
- `macos/build/branding-2026-10-25/about-new-icon.png` — 実画面の記録。

## 作業範囲と状態

既存のパフォーマンス・UI/UX 監査修正、上流所有のルート README とソース、
ライセンス、クレジット、非公式ポート表記を維持した。実ライブラリ設定と
Dropbox の同期・参照先は変更していない。

今回はローカルのソースと生成アプリを更新した。`/Applications` のインストール済み
アプリの置き換え、GitHub への push、リリース公開はこの変更では実施していない。
バージョン番号は 0.3.1 のまま。
