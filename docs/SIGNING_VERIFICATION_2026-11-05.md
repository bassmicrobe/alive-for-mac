# Developer ID 署名・公証の検証記録（2026-11-05）

## 対象と実行

- リポジトリ: `bassmicrobe/alive-for-mac`
- 対象: `main` のアプリ 0.3.2（ベース `fa559cda351878c5485f7cefdf5e465dbff57633`）に署名・公証対応を追加。
- 検証コミット: `fdfb930016467549e1acb32cea3211c17a553a6b`
- 検証方法: `signing-verify-20261105-one-runner` タグへの push（公開しない検証モード）
- [GitHub Actions 実行](https://github.com/bassmicrobe/alive-for-mac/actions/runs/41888546538)
- [変更を確認する Draft PR #6](https://github.com/bassmicrobe/alive-for-mac/pull/6)
- チーム: Cybereye Technology Co., Ltd. / `8XUK86NH38`
- 証明書: `Developer ID Application: Cybereye Technology Co., Ltd. (8XUK86NH38)`

ローカルの未公開 0.4 系機能変更は検証対象に含めていない。Release 公開用のタグは作成しない。

## 結果

**失敗。登録済み p12 と書き出し用パスワードの組による MAC 検証で停止した。**
署名・公証は未実行。5つの Secret の名前が存在することだけで、設定完了とは判断しない。

| 確認項目 | 結果 |
| --- | --- |
| 5つの repository Secret の名前 | すべて存在 |
| 資格情報処理のテスト | 3件成功 |
| Swift ビルド・全テスト | 1,009件、12件スキップ、失敗0 |
| p12 の MAC 検証 | `Mac verify error: invalid password?` で失敗 |
| Developer ID 取り込み・Apple 資格情報検証 | MAC 検証の失敗により未実行 |
| universal app・拡張・DMG の署名 | 未実行 |
| アプリと DMG の Apple 公証 | 未実行 |
| stapler / codesign / Gatekeeper | 未実行 |
| Actions artifact 保存 | 未実行 |
| 一時キーチェーン・p12 の終了処理 | 成功（キーチェーン作成前に停止、p12 は finally で削除） |
| GitHub Release 公開 | スキップ |

実行一覧の独立した `Build and test` ジョブは、このタグ実行では設計通りスキップ。
`Package and release` 内の `Build and test` ステップで全テストを実行して成功している。

p12 のパスワード値は読み出せない。今回の Secret の組を正常とは確認できなかった。
OpenSSL 4 の既定形式で作った別のダミー p12 は、同じパスワードを標準入力に渡して
このMacの OpenSSL 4.0.3 と `/usr/bin/openssl`（LibreSSL 3.3.6）の両方で MAC 検証に成功した。
従って、単に OpenSSL 4 の既定形式であることだけを今回の MAC エラーの原因とは扱わない。
秘密の値を推測・表示せず、対応する証明書・秘密鍵から p12 と書き出し用パスワードを一組で
用意し直し、ローカルの MAC 検証に成功してから両 Secret を再登録する必要がある。


## 今回修正した点

- `main` のワークフローは従来 ad-hoc 署名のみ。Developer ID 署名、アプリ・DMG の公証、
  staple、配布 ZIP 内アプリの検証、独立した Gatekeeper 判定を追加した。
- `verify_only=true` が手動実行の既定値。`signing-verify-*` タグも公開を伴わない検証に使用する。
  パッケージは7日間の Actions artifact に保存する。通常のブランチ・PRテストには資格情報を渡さない。
- テスト後の新しいランナー割り当て待ちを避けるため、公開・公証検証では全テストと署名・公証を
  同じランナーの1ジョブで実行する。テスト失敗時は資格情報を取り込む前に停止する。
- OpenSSL 4.0.3 の既定 p12 は macOS の取り込みで誤解を招くパスフレーズエラーになった。
  ダミー証明書ではこの形式差を再現し、CI 内で元の p12 の MAC を検証してから互換形式の一時 p12 に変換するよう修正。
  ただし今回の実行は MAC 検証に失敗したため、変換には到達していない。
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
今回の停止箇所は手順書の「MAC 検証で失敗した場合」を参照。
書き出し直せる秘密鍵付き証明書または利用可能な p12 バックアップの有無を所有者と確認する。
ローカルへの取り込みは先の作業でキャンセルしており、署名用 identity の存在は未確認。
対応する秘密鍵が無い場合、`.cer` だけから復元できない。既存証明書を失効させず、所有者と対応を決める。
App 用パスワードは今回まだ検証に到達していないため、推測で再発行しない。
PR の変更を `main` に取り込むまでは、署名対応ブランチのワークフローを明示して実行する。
