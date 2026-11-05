# Developer ID 署名・公証の検証記録（2026-11-05）

> **この記録の範囲:** PR #6（`codex/verify-signing-notarization`、0.3.2 ベース）の検証用ワークフローでの結果。
> 確かめられたのは、登録した5つの Secret の値が正しいことと、Apple が公証を受理することまで。
> 0.4.0 の署名・公証は別の実装（[RELEASING.md](RELEASING.md)）で、`ci-signing.py`・`signing-verify-*` タグ・
> `notary_status_only` は 0.4.0 のワークフローには無い。下の「今回修正した点」は PR #6 のブランチの内容。

## 対象と実行

- リポジトリ: `bassmicrobe/alive-for-mac`
- 対象: `main` のアプリ 0.3.2（ベース `fa559cda351878c5485f7cefdf5e465dbff57633`）に署名・公証対応を追加。
- 検証コミット: `ace735db436534b6b568c442814d5ba81d0247cd`
- 検証方法: `signing-verify-20261105-recovered` タグへの push（公開しない検証モード）
- [GitHub Actions 実行](https://github.com/bassmicrobe/alive-for-mac/actions/runs/41952554918)
- [変更を確認する Draft PR #6](https://github.com/bassmicrobe/alive-for-mac/pull/6)
- チーム: Cybereye Technology Co., Ltd. / `8XUK86NH38`
- 証明書: `Developer ID Application: Cybereye Technology Co., Ltd. (8XUK86NH38)`

ローカルの未公開 0.4 系機能変更は検証対象に含めていない。Release 公開用のタグは作成しない。

## 結果

**成功。アプリと DMG の署名・公証・staple・Gatekeeper 検証がすべて通った。**
初回の p12 MAC 検証失敗から復旧し、新しい証明書・秘密鍵入り p12 と、所有者がコピーした
実際の書き出し用パスワードの一致をローカルで確認して両 Secret を更新した。

| 確認項目 | 結果 |
| --- | --- |
| 5つの repository Secret の名前 | すべて存在 |
| ローカルの p12 MAC・証明書・秘密鍵の一致 | すべて成功 |
| 資格情報処理のローカルテスト | 4件成功 |
| Actions のビルド・全テスト | 1,009件、12件スキップ、失敗0。資格情報処理4件も成功 |
| Developer ID 取り込み・Apple 資格情報検証 | 成功 |
| universal app・拡張・DMG の署名 | 成功。arm64/x86_64、Developer ID、hardened runtime、timestamp を確認 |
| アプリと DMG の Apple 公証 | 両方 `Accepted` |
| stapler / codesign / Gatekeeper | アプリ・DMG・ZIP内アプリの検証に成功。`source=Notarized Developer ID` |
| Actions artifact 保存 | `notarized-macos-packages`、ZIP と DMG を保存 |
| runner の一時キーチェーン・p12 の終了処理 | 成功 |
| ローカルの p12・一時パスワード・補助プログラム | 削除済み、クリップボード消去済み |
| GitHub Release 公開 | スキップ。公開済みアセットは変更していない |

実行一覧の独立した `Build and test` ジョブは、このタグ実行では設計通りスキップ。
`Package and release` 内の `Build and test` ステップで全テストを実行して成功している。

artifact ID は `13383768763`。保存期限は **2026-11-12 11:53 JST**（7日間）。
Actions 実行ページから `AliveForMac-0.3.2.zip` と `AliveForMac-0.3.2.dmg` を取得できる。
この検証はアプリをこのMacにインストールする作業とは別で、既存の公開Releaseも更新していない。

## Apple 側の受付状況

[照会専用ジョブ](https://github.com/bassmicrobe/alive-for-mac/actions/runs/41956632810)は成功。
本体の検証をキャンセルせず、再送せずに Apple の履歴を照会した。

- 対象: `Alive for Mac.zip`
- 申請ID: `c3e860a1-8155-42d6-b599-92a0ce009584`
- 受付日時: 2026-11-05 11:09 JST
- 2026-11-05 11:39 JST の途中照会結果: `In Progress`
- アプリの最終結果: `Accepted`（2026-11-05 11:52 JST）
- DMG の申請ID: `5252a822-18d6-4b5e-80ea-9c510a289ea5`
- DMG の最終結果: `Accepted`（2026-11-05 11:53 JST）
- 照会ジョブのビルド・公開はスキップ、使い捨てキーチェーンの削除は成功。

11:39 JST の照会結果は途中経過であり、後続の本体検証で両方の `Accepted` を確認した。
アプリの受付から受理までは今回約44分かかった。待機時間だけを理由に資格情報を再発行しない。

## 復旧の記録

[初回の実検証](https://github.com/bassmicrobe/alive-for-mac/actions/runs/41888546538)では、
資格情報処理3テストと Swift 1,009テスト（12スキップ、失敗0）は成功したが、
登録済み p12 とパスワードの MAC 検証に失敗。署名・公証には到達しなかった。

`.cer` は公開証明書であり秘密鍵を含まない。利用可能な p12 や秘密鍵のバックアップは
無いとの所有者の回答を受け、Macの証明書アシスタントで RSA 2048bit の鍵ペアと CSR を作成。
同じチームの Developer ID Application 証明書を発行し、CSRとの公開鍵一致を確認して
ログインキーチェーンへ取り込んだ。既存の証明書は失効させていない。

- 新しい証明書ID: `M3M5AHH47V`
- SHA-256: `C7747868782FACDCC8C21678DF79F32219003DDF834E7AADBAF532F3AC92E3F9`
- 有効期限: 2027-12-05（証明書の記録）
- ローカル秘密鍵のラベル: `Alive for Mac Developer ID 2026-11-05`

キーチェーンの「自分の証明書」で秘密鍵の付属を確認。書き出した p12 を準備済みの
パスワードで開く検証は失敗したが、所有者が実際の書き出し用パスワードをコピーした後は成功した。
p12内の証明書が新しい証明書と一致し、秘密鍵から得た公開鍵も証明書の公開鍵と一致することを
確認してから p12 とパスワードの両 Secret を標準入力で更新した。値は出力していない。

Mac標準の p12 は OpenSSL 4 の通常読み込みで `unsupported` になり、`-legacy` 付きでは
MAC 検証・復号とも成功した。CIにはこの形式の読み込み対応とテストを追加した。
秘密鍵はMacに保持し、書き出した p12、一時パスワード、失敗した書き出し補助プログラムは削除した。


## 今回修正した点

- `main` のワークフローは従来 ad-hoc 署名のみ。Developer ID 署名、アプリ・DMG の公証、
  staple、配布 ZIP 内アプリの検証、独立した Gatekeeper 判定を追加した。
- `verify_only=true` が手動実行の既定値。`signing-verify-*` タグも公開を伴わない検証に使用する。
  パッケージは7日間の Actions artifact に保存する。通常のブランチ・PRテストには資格情報を渡さない。
- テスト後の新しいランナー割り当て待ちを避けるため、公開・公証検証では全テストと署名・公証を
  同じランナーの1ジョブで実行する。テスト失敗時は資格情報を取り込む前に停止する。
- OpenSSL 4.0.3 の既定 p12 は macOS の取り込みで誤解を招くパスフレーズエラーになった。
  ダミー証明書ではこの形式差を再現し、CI 内で元の p12 の MAC を検証してから互換形式の一時 p12 に変換するよう修正。
  初回の実行は MAC 検証に失敗したため、変換には到達しなかった。
  登録済みの Secret 自体は変更していない。
- `notary_status_only=true` の手動実行では照会ジョブだけを実行する。再ビルド・再送・公開はせず、
  本体検証とは別の concurrency group で、対象アプリの申請情報だけを表示する。実際の照会も成功。
- パスワードは標準入力または echo を無効にした端末へ渡す。一時 PEM・p12 を削除し、
  ワークフローの終了処理で使い捨てキーチェーンを削除する。失敗時も復号した標準出力をログに出さない。
- Swift 6.2 で既存のサンプルパス置換の文字列型推論が失敗したため、`String` への変換を明示。
  関連7テストはローカルで成功した。

ローカルでも資格情報処理4テスト、native notarytool のダミー資格情報のプロンプト保存、
OpenSSL p12 形式の取り込み比較と変換後の取り込み、シェル構文とワークフロー YAML を確認した。
ダミー証明書・一時キーチェーンは削除済み。実際の秘密の値は文書に残さない。

## 次回

[設定・再検証の手順書](SIGNING_SETUP_RUNBOOK.ja.md)を使う。
今回用意した秘密鍵付き証明書はログインキーチェーンに残っている。
p12を再登録する場合は、この証明書から書き出し、実際の書き出し用パスワードで MAC を検証する。
証明書や App 用パスワードを推測で再発行しない。
PR の変更を `main` に取り込むまでは、署名対応ブランチのワークフローを明示して実行する。
