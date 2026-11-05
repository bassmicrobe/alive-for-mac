# Developer ID 署名・公証の初期設定と再検証

対象: `bassmicrobe/alive-for-mac`。2026-11-05 の設定作業で確認した手順。
秘密の値はこの文書、チャット、スクリーンショット、ログ、コマンド引数に保存しない。

## 今回の設定記録

- チーム: Cybereye Technology Co., Ltd.
- Team ID: `8XUK86NH38`
- 証明書: `Developer ID Application: Cybereye Technology Co., Ltd. (8XUK86NH38)`
- App 用パスワードの用途名: `alive-for-mac notarytool`
- 登録先: このリポジトリの Actions repository secrets。
- 初回の Actions は p12 の MAC 検証で停止。新しい秘密鍵付き証明書を用意し、所有者が
  コピーした書き出し用パスワードで MAC・証明書・秘密鍵の一致を確認して両 Secret を更新。
  再検証ではアプリ・DMGとも `Accepted`、staple・配布 ZIP・Gatekeeper の検証と終了処理も成功。
- p12 と Base64 の値、各パスワード、Apple Account の認証コードは記録しない。
- 一時 p12・CSR・秘密鍵ファイルを削除し、クリップボードを消去済み。
- 最初の p12 取り込みは認証エラーの後にキャンセル。復旧時はキーチェーンの証明書
  アシスタントで CSR を作り直し、新しい秘密鍵をログインキーチェーンに保持した。
  「自分の証明書」の対象証明書を展開し、秘密鍵 `Alive for Mac Developer ID 2026-11-05` の付属を確認済み。
- 復旧時の証明書ID: `M3M5AHH47V`、SHA-256:
  `C7747868782FACDCC8C21678DF79F32219003DDF834E7AADBAF532F3AC92E3F9`。
  同じ証明書名が複数ある場合は、名前だけでなく指紋と秘密鍵の対応を確認する。既存証明書は失効させていない。
- このMacのキーチェーンでは証明書の信頼警告が表示された。信頼設定は変更していない。
  秘密鍵の付属とローカルの信頼チェーンは別の確認事項で、ローカルでの署名は今回の検証対象外。
  GitHubのランナーでは対象チームの有効な署名 identity として取り込めた。

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
画面を引き継ぐときは対象タブを前面に出し、ブラウザ名とタブ名を伝える。
Chromeで見つからない場合は `Shift + Command + A` のタブ検索で「サインイン - Apple」を探せる。

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

対象証明書の行をクリックして選択し、ファイル →「書き出す…」を使う。
検索欄にフォーカスしたままだと「書き出す…」が無効になる場合がある。
今回のMacでは右クリックのメニューに書き出しが無かったため、ファイルメニューを使用した。

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

パスワードを生成しても、後の画面操作や所有者の操作でクリップボードの内容が変わることがある。
今回も準備済みの値では検証に通らず、所有者が実際の書き出し用パスワードをコピーした後に
一致を確認できた。ファイルの存在だけで成功と扱わず、実際に書き出しに使った値を検証する。

GitHub は Secret の値を後から読み戻せない。ローカル署名にも使うなら、削除前に
秘密鍵付き identity がキーチェーンに保存できているか確認する。
クリップボードが別の内容に変わったら、推測した値で既存 Secret を上書きしない。

### OpenSSL 3/4 で作った p12 の互換性

OpenSSL 4.0.3 の既定形式で作ったダミー p12 では、パスワードが正しくても macOS の
`SecKeychainItemImport` が「The user name or passphrase you entered is not correct」で拒否した。
オフラインで、既定形式の取り込み失敗・互換形式の取り込み成功を再現済み。
パスワードの誤りと即断せず、まず OpenSSL の MAC 検証で一致を確認する。

OpenSSL で書き出す場合の互換オプションは
`-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg SHA1`。
パスワードは引き続き `-passout stdin` で渡す。
0.4.0 の CI は p12 を OpenSSL を通さず `security import` で直接取り込むため、この変換はしない
（キーチェーンアクセスが書き出した p12 はそのまま取り込める）。OpenSSL で作った p12 を登録するときだけ、
上の互換オプションで作る。

### Mac 標準の p12 を OpenSSL 3/4 で読む場合

キーチェーンアクセスが書き出した p12 は、証明書バッグの暗号形式によって
OpenSSL 3/4 で `unsupported`（例: RC2-40-CBC）になることがある。
今回の復旧用 p12 では、標準 LibreSSL の検証成功、OpenSSL 4 の通常読み込み失敗、
`-legacy` を付けた MAC 検証・読み込み成功を確認した。
[OpenSSL公式の説明](https://docs.openssl.org/4.0/man1/openssl-pkcs12/)も参照。

```sh
# Mac 標準の LibreSSL を明示し、値を表示せず確認
pbpaste | /usr/bin/openssl pkcs12 -in ~/Desktop/DeveloperID.p12 -noout -passin stdin
# OpenSSL 3/4 で unsupported が出る場合だけ legacy provider を使う
pbpaste | openssl pkcs12 -legacy -in ~/Desktop/DeveloperID.p12 -noout -passin stdin
```

ローカルで値を確かめるときだけの話で、CI は OpenSSL を使わない。MAC 検証を無効にする `-nomacver` は使わない。

### MAC 検証で失敗した場合

`Mac verify error: invalid password?` が OpenSSL の MAC 検証で出た場合、
`SecKeychainItemImport` の形式互換性エラーとは別に扱う。MAC 検証を無効にして先へ進まない。
初回の Actions 実行はこの段階で停止し、互換形式への変換・署名・公証には到達しなかった。
別のダミー p12 は OpenSSL 4 と標準 LibreSSL の両方で MAC 検証に成功しているため、
今回の失敗を OpenSSL 4 の既定形式だけが原因と断定しない。

1. 秘密鍵付き証明書またはパスワードが分かる p12 バックアップの有無を所有者と確認する。
2. p12 を書き出し直す場合は、新しい書き出し用パスワードを生成し、**同じ組**として用意する。
3. クリップボードの値を表示せず、登録前にローカルで一致を確認する。

   ```sh
   pbpaste | /usr/bin/openssl pkcs12 -in ~/Desktop/DeveloperID.p12 -noout -passin stdin
   ```

4. 検証成功後、手順3の2コマンドで p12 とパスワードの両 Secret を登録し、後片付け・Actions 再検証。

秘密鍵が無い場合、公開証明書 `.cer` だけでは p12 を復元できない。
既存証明書を勝手に失効させず、所有者と対応を決める。
App 用パスワードはこの失敗だけを理由に作り直さない。

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

タグを打つ前に、公開せずに署名・公証だけを通す。`macOS CI` の手動実行は `verify_only` が既定で true。

```sh
gh workflow run macos-ci.yml -R bassmicrobe/alive-for-mac --ref <ブランチ>
gh run list -R bassmicrobe/alive-for-mac --workflow macos-ci.yml --limit 5
gh run watch <run-id> -R bassmicrobe/alive-for-mac
```

- テスト（`Build and test`）のあと `Package and release` が署名・公証まで行い、zip と dmg を
  7日間の artifact `macos-packages` に保存する。GitHub Release は作らず、既存のものも変えない。
- 公開用の `v*` タグの push では、同じ手順のあと Release を作る。手動実行で公開したいときだけ
  `-f verify_only=false` を付ける。
- 同じブランチへの push は、手動の検証実行を中断しない（concurrency group をイベントごとに分けている）。
- 公証の待ちは1回あたり最大60分、ジョブ全体は150分まで。2026-11-05 はアプリの公証に約44分かかった。
  `In Progress` が続くだけで証明書や App 用パスワードを作り直さない。
  待ちの途中の状況は、手元で `xcrun notarytool history --keychain-profile <プロファイル>` で見られる。

成功の判断は以下のすべてを満たした場合（どれもジョブの中で確かめ、満たさなければ失敗する）。

- 5つの Secret がそろい、p12 の取り込みに成功し、対象 Team ID の `Developer ID Application` identity がある。
- `notarytool store-credentials` で Apple が公証用の資格情報を受け付ける。
- arm64・x86_64 の universal app と両拡張を Developer ID、hardened runtime、timestamp 付きで署名。
- アプリと DMG の両方の公証が `Accepted`。
- アプリ・DMG・配布 ZIP 内のアプリで `stapler validate` が成功。
- `codesign --verify --deep --strict`、`spctl` が成功し、アプリは `Notarized Developer ID` と判定。
- 成否にかかわらず runner の使い捨てキーチェーンと p12 を削除。

CI の手順の詳細は [RELEASING.md](RELEASING.md) の「CI で起きること」。

## 参考（Apple公式）

- [Developer ID 証明書](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [アカウントの役割](https://developer.apple.com/help/account/access/roles)
- [App 用パスワード](https://support.apple.com/HT204397)
- [CSR の作成](https://developer.apple.com/help/account/create-certificates/create-a-certificate-signing-request)

実際の Actions の実行URL・結果は[検証記録](SIGNING_VERIFICATION_2026-11-05.md)を参照。
実行前の段階で「公証済み」と記録しない。
