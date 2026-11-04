# Developer ID 署名・公証の検証記録（2026-11-05）

## 対象と実行

- リポジトリ: `bassmicrobe/alive-for-mac`
- 対象: `main` のアプリ 0.3.2（ベース `fa559cda351878c5485f7cefdf5e465dbff57633`）に署名・公証対応を追加。
- 検証コミット: `8205430beca30999f3e569f74e1a5cdf6db0c88f`
- 検証タグ: `signing-verify-20261105`
- [GitHub Actions 実行](https://github.com/bassmicrobe/alive-for-mac/actions/runs/41884659719)
- [変更を確認する Draft PR #6](https://github.com/bassmicrobe/alive-for-mac/pull/6)
- チーム: Cybereye Technology Co., Ltd. / `8XUK86NH38`
- 証明書: `Developer ID Application: Cybereye Technology Co., Ltd. (8XUK86NH38)`

ローカルの未公開 0.4 系機能変更は検証対象に含めていない。Release 公開用のタグは作成しない。

## 結果

実行中。ビルド・テスト完了後、署名・公証ジョブのランナー割り当て待ち。
公証成功の判定はまだ行っていない。

| 確認項目 | 結果 |
| --- | --- |
| 5つの repository Secret の名前 | すべて存在 |
| 資格情報処理のテスト | 3件成功 |
| Swift ビルド・全テスト | 1,009件、12件スキップ、失敗0 |
| Developer ID 取り込み・Apple 資格情報検証 | 待機中 |
| universal app・拡張・DMG の署名 | 待機中 |
| アプリと DMG の Apple 公証 | 待機中 |
| stapler / codesign / Gatekeeper | 待機中 |
| Actions artifact 保存 | 待機中 |
| 一時キーチェーン・p12 の削除 | 待機中 |
| GitHub Release 公開 | 検証モードでスキップする設定 |

## 今回修正した点

- `main` のワークフローは従来 ad-hoc 署名のみ。Developer ID 署名、アプリ・DMG の公証、
  staple、配布 ZIP 内アプリの検証、独立した Gatekeeper 判定を追加した。
- `verify_only=true` が手動実行の既定値。`signing-verify-*` タグも公開を伴わない検証に使用する。
  パッケージは7日間の Actions artifact に保存する。通常のブランチ・PRテストには資格情報を渡さない。
- OpenSSL 4.0.3 の既定 p12 は macOS の取り込みで誤解を招くパスフレーズエラーになった。
  ダミー証明書で再現した後、CI 内で元の p12 の MAC を検証して互換形式の一時 p12 に変換するよう修正。
  登録済みの Secret 自体は変更していない。
- パスワードは標準入力または echo を無効にした端末へ渡す。一時 PEM・p12 を削除し、
  ワークフローの終了処理で使い捨てキーチェーンを削除する。失敗時も復号した標準出力をログに出さない。
- Swift 6.2 で既存のサンプルパス置換の文字列型推論が失敗したため、`String` への変換を明示。
  関連7テストはローカルで成功した。

ローカルでも資格情報処理3テスト、native notarytool のダミー資格情報のプロンプト保存、
OpenSSL p12 形式の取り込み比較と変換後の取り込み、シェル構文とワークフロー YAML を確認した。
ダミー証明書・一時キーチェーンは削除済み。実際の秘密の値は文書に残さない。

## 次回

[設定・再検証の手順書](../macos/docs/SIGNING_SETUP_RUNBOOK.ja.md)を使う。
5つの Secret が存在するなら、証明書や App 用パスワードを作り直さず、まず検証する。
PR の変更を `main` に取り込むまでは、署名対応ブランチのワークフローを明示して実行する。
