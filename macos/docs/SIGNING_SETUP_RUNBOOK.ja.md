# Developer ID 署名・公証の初期設定と再検証

対象: `bassmicrobe/alive-for-mac`。2026-11-05 の設定作業で確認した手順。
秘密の値はこの文書、チャット、スクリーンショット、ログ、コマンド引数に保存しない。

## 今回の設定記録

- チーム: Cybereye Technology Co., Ltd.
- Team ID: `8XUK86NH38`
- 証明書: `Developer ID Application: Cybereye Technology Co., Ltd. (8XUK86NH38)`
- App 用パスワードの用途名: `alive-for-mac notarytool`
- 登録先: このリポジトリの Actions repository secrets。
- p12 と Base64 の値、各パスワード、Apple Account の認証コードは記録しない。
- 一時 p12・CSR・秘密鍵ファイルを削除し、クリップボードを消去済み。
- このMacへの p12 取り込みは認証エラーの後にキャンセル。ローカルキーチェーンに
  署名用 identity があるとは限らない。GitHub Secrets の登録とは別に扱う。

## 次回の最短経路

既に5つの Secret がある場合は、証明書や App 用パスワードを作り直さず、まず
「Actions で検証」を実行する。エラーになった Secret だけを更新する。
証明書や既存の App 用パスワードを勝手に失効・削除しない。

## 1. アカウントと契約の確認

1. `gh auth status` で GitHub CLI のログインを確認。未ログインなら所有者が `gh auth login`。
2. [App Store Connect のユーザ一覧](https://appstoreconnect.apple.com/access/users)で対象チームを選ぶ。
   自分の役割に **Account Holder** があるか確認する。自分の Apple Account というだけでは不十分。
3. [Apple Developer のアカウント](https://developer.apple.com/account/)のメンバーシップ詳細でも
   チーム名、Team ID、Account Holder、自分の役割を照合する。
4. 最新の Apple Developer Program License Agreement の同意待ちがあれば、所有者が内容を読み、
   同意する場合のみ自分で操作する。契約未同意が個々のエラーの原因とは即断しない。

Apple Account のサインイン、2FA、Mac・キーチェーンのパスワード入力は所有者が行う。
エージェントには値を渡さず、入力が終わったことだけを伝える。

今回、Web では Account Holder、Xcode では同じアカウント・チームが Admin と表示された。
Xcode の「This operation can only be performed by the Account Holder」だけで
本人が Account Holder ではないと断定しない。

## 2. 証明書と秘密鍵を用意する

キーチェーンアクセス → ログイン → 自分の証明書で **Developer ID Application** を探す。
開閉用三角を開き、秘密鍵が付属し、Team ID が対象チームと一致する有効な証明書を使う。
`Developer ID Installer` や `Apple Distribution` は今回の用途には使わない。

証明書が無ければ Xcode → Settings → Apple Accounts → 対象チーム → Manage Certificates →
「+」→ Developer ID Application。通常の Developer ID 証明書の作成には Account Holder が必要。
Cloud-managed 証明書の権限は、秘密鍵付き p12 を用意する今回の方法とは区別する。

### Xcode で作れない場合の Web 発行

1. このMacの「キーチェーンアクセス → 証明書アシスタント → 認証局に証明書を要求」で CSR を
   **ディスクに保存**する。秘密鍵はこのMacに作られる。
2. [証明書一覧](https://developer.apple.com/account/resources/certificates/list) →「+」→
   **Developer ID Application** → Continue → CSR を指定して発行。
3. ダウンロードした `.cer` を CSR を作成した同じMacのキーチェーンに取り込む。
   `.cer` だけには秘密鍵がない。別のMacの秘密鍵とは組み合わせられない。
4. 秘密鍵が付属することを確認して p12 を書き出す。

今回の Web 発行では OpenSSL で作った RSA 2048bit の CSR と対応する秘密鍵を使用した。
この代替方法を使う場合、作業用ディレクトリは `0700`、秘密鍵は `0600` とし、
証明書の公開鍵と秘密鍵から取り出した公開鍵の一致を確認してから p12 を作る。
秘密鍵を引数・画面・ログへ出力しない。作業後は秘密鍵も削除する。

## 3. p12 とパスワードの登録

強い書き出し用パスワードを、表示せずクリップボードへ入れる。

```sh
openssl rand -base64 24 | tr -d '\n' | pbcopy
```

対象の証明書と秘密鍵を個人情報交換 `.p12` として `~/Desktop/DeveloperID.p12` へ書き出し、
パスワードと確認欄に貼り付ける。キーチェーンのパスワードを求められたら所有者が入力。
**クリップボードを別の用途に使う前に**、すぐにパスワードを登録する。

```sh
pbpaste | gh secret set APPLE_DEVELOPER_ID_P12_PASSWORD -R bassmicrobe/alive-for-mac
base64 -i ~/Desktop/DeveloperID.p12 | gh secret set APPLE_DEVELOPER_ID_P12 -R bassmicrobe/alive-for-mac
```

OpenSSL で p12 を作る場合も `-passout stdin` またはファイル記述子を使う。
`-passout pass:...`、`security import -P ...` のように秘密の値をプロセスの引数へ入れない。
必要なら Python の `subprocess.run(..., input=...)` から標準入力で渡す。

GitHub は Secret の値を後から読み戻せない。ローカル署名にも使うなら、削除前に
秘密鍵付き identity がキーチェーンに保存できているか確認する。
クリップボードが別の内容に変わったら、推測した値で既存 Secret を上書きしない。

### OpenSSL 3/4 で作った p12 の互換性

今回、OpenSSL 4.0.3 の既定形式で作った p12 は、パスワードが正しくても macOS の
`SecKeychainItemImport` が「The user name or passphrase you entered is not correct」で拒否した。
オフラインのダミー証明書で、既定形式の取り込み失敗・互換形式の取り込み成功を再現済み。
パスワードの誤りと即断せず、まず OpenSSL の MAC 検証で一致を確認する。

OpenSSL で書き出す場合の互換オプションは
`-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg SHA1`。
パスワードは引き続き `-passout stdin` で渡す。
CI の `ci-signing.py` は元の p12 を OpenSSL で検証した後、runner 内の一時コピーを
この形式に変換する。GitHub Secret 自体は変更しない。一時的に復号した PEM と
互換 p12 も、成功・失敗の両方で削除する。復号した標準出力をエラーログに出さない。

## 4. Apple ID、Team ID、App 用パスワード

登録名は次の5つ。値の確認は所有者と、対象チームのメンバーシップ詳細で行う。

| Secret | 値 |
| --- | --- |
| `APPLE_DEVELOPER_ID_P12` | 秘密鍵付き p12 の Base64 |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | p12 の書き出し用パスワード |
| `APPLE_NOTARY_APPLE_ID` | Developer Program に登録した Apple Account のメールアドレス |
| `APPLE_NOTARY_PASSWORD` | そのアカウントの App 用パスワード |
| `APPLE_TEAM_ID` | 証明書とメンバーシップに一致する10文字の Team ID |

[Apple Account](https://account.apple.com/) → サインインとセキュリティ → アプリ用パスワード →
生成 → 用途名 `alive-for-mac notarytool`。再認証は所有者が操作する。
新しい認証情報の発行について、操作ツールが直前の承認を必要とする場合はその時点で確認する。

表示された `xxxx-xxxx-xxxx-xxxx` を選択してコピーし、値を表示せず登録する。
今回、最初のコピーではクリップボードに値が入っていなかったため、発行画面で再選択してコピーした。
値が発行画面に残っていれば、同じ用途のパスワードを繰り返し発行する必要はない。

```sh
pbpaste | gh secret set APPLE_NOTARY_PASSWORD -R bassmicrobe/alive-for-mac
gh secret set APPLE_NOTARY_APPLE_ID -R bassmicrobe/alive-for-mac
gh secret set APPLE_TEAM_ID -R bassmicrobe/alive-for-mac
```

後ろ2つは対話入力する。Apple Account の通常のログインパスワードは Secret に登録しない。
自動操作で発行結果を読む場合は生の画面ツリーやスクリーンショットをログへ出さない。

## 5. 後片付けと登録確認

```sh
rm -P ~/Desktop/DeveloperID.p12
pbcopy < /dev/null
gh secret list -R bassmicrobe/alive-for-mac
```

自分で作った CSR、一時秘密鍵、Base64 ファイルがあればそれらも削除する。
Base64 を直接パイプに流せば Base64 ファイルは不要。既存の他の証明書・鍵を削除しない。
`gh secret list` は名前の存在確認であり、正しい値かどうかは Actions の実行で確認する。
APFS/SSD 上の削除を、物理的な完全消去と表現しない。

## 6. Actions で検証

署名対応の `macOS CI` を使う。手動実行では `verify_only=true` を指定する。

```sh
gh workflow run macos-ci.yml -R bassmicrobe/alive-for-mac \
  --ref <署名対応ブランチ> -f verify_only=true
gh run list -R bassmicrobe/alive-for-mac --workflow macos-ci.yml --limit 5
gh run view <run-id> -R bassmicrobe/alive-for-mac
```

`signing-verify-*` タグへの push でも同じ署名・公証の検証を実行する。
この検証用タグでは公開処理を実行しない。手動実行が滞留する場合も、固有のタグなら
既存のブランチ実行とは別の concurrency group で検証できる。公開用の `v*` タグと区別する。

検証モードでは GitHub Release の作成・既存アセットの置換はスキップし、パッケージを
7日間の Actions artifact として保存する。タグ実行では通常の公開処理を行う。
古い `main` のワークフローには署名処理も検証モードも無い場合があるため、実行する ref の内容を確認。
手動実行の `runner` は既定で `macos-26`。長く割り当て待ちになる場合は `-f runner=macos-15`
を指定して検証できる。ランナーを変えても署名・公証・Gatekeeper の検証条件は同じ。

成功の判断は以下のすべてを満たした場合。

- 5つの Secret の存在確認と p12 の取り込みに成功し、対象 Team ID の有効な署名 identity がある。
- Apple が公証用の資格情報を検証できる。
- arm64・x86_64 の universal app と両拡張を Developer ID、hardened runtime、timestamp 付きで署名。
- アプリと DMG の両方の公証が `Accepted`。
- アプリ・DMG・配布 ZIP 内のアプリで `stapler validate` が成功。
- `codesign --verify --deep --strict`、`spctl` が成功し、アプリは `Notarized Developer ID` と判定。
- 成否にかかわらず runner の使い捨てキーチェーンと p12 を削除。

CI の `ci-signing.py` はキーチェーンのパスワードを `security -i` の標準入力へ渡し、
App 用パスワードは echo を無効にした端末の `notarytool` プロンプトへ入力する。
値をコマンド引数やエラーログへ出さず、保存後のビルドには keychain profile の名前だけを渡す。

## 参考（Apple公式）

- [Developer ID 証明書](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [アカウントの役割](https://developer.apple.com/help/account/access/roles)
- [App 用パスワード](https://support.apple.com/HT204397)
- [CSR の作成](https://developer.apple.com/help/account/create-certificates/create-a-certificate-signing-request)

実際の Actions の実行URL・結果は検証記録に追記する。実行前の段階で「公証済み」と記録しない。
