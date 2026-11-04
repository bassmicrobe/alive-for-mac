# リリースの署名と公証 / Release signing and notarization

日本語が前半、English は後半です。 / Japanese first, English below.

今回の実設定と再利用できる手順: [署名・公証セットアップ手順書](SIGNING_SETUP_RUNBOOK.ja.md)。
手動検証は `verify_only=true`（既定）で実行し、公開リリースを作成・置換しません。

---

## 日本語

タグ `v<version>`（`macos/VERSION` と同じ番号）を push すると、`.github/workflows/macos-ci.yml` の
`release` ジョブが `AliveForMac-<version>.zip` と `.dmg` を作って GitHub Release に載せます。

- **Apple の資格情報（下の 5 つのシークレット）が登録されている場合:** Developer ID Application
  証明書で署名し、Apple に公証（notarize）を依頼し、チケットをアプリと DMG に staple します。
  ダウンロードした利用者の Mac では、Gatekeeper の操作なしで開けます。
- **5 つとも無い場合:** これまでどおり ad-hoc 署名のビルドを作ります。ワークフローは
  `::warning::Release is ad-hoc signed and not notarized (missing secrets: …)` を出し、リリースを
  新規作成するときだけ本文の先頭に「公証されていない・「このまま開く」が必要」という注意書き
  （日本語と英語）を付けます。既存のリリースへの上書きアップロードでは本文は変えません。
- **一部だけ欠けている場合（1〜4 個が登録済み）:** シークレットの登録ミスとみなし、
  `Decide signing mode` が `::error::` を出してジョブを失敗させます。ad-hoc のビルドは作りません。
- **ad-hoc のビルドを既存のリリースに上書きすることはしません。** シークレットが無いまま同じタグで
  再実行すると、公証済みのファイルを ad-hoc 署名のものに置き換えてしまうためです。既存のリリースが
  あり、かつ署名されていないビルドのときは `Publish GitHub Release` が失敗します。本当に上書きしたい
  ときだけ、Actions から手動実行（`workflow_dispatch`）して boolean の入力 `allow_adhoc_overwrite`
  を true にします（既定は false。タグの push では常に false）。

### 1. 一度だけ行う準備

前提: Apple Developer Program（有料）に加入していること。

1. **Developer ID Application 証明書を作る。**
   - Xcode → Settings → Accounts → 自分のチームを選ぶ → Manage Certificates… → 左下の「+」→
     **Developer ID Application**。
   - または developer.apple.com → Certificates, Identifiers & Profiles → 「+」→ Developer ID Application
     （Keychain Access の「証明書アシスタント」で作った CSR をアップロード）。
   - Developer ID 証明書を作れるのはAccount Holder（通常の秘密鍵付き Developer ID 証明書の場合）です。
2. **.p12 を書き出す。** Keychain Access → 「ログイン」→「自分の証明書」で
   `Developer ID Application: 名前 (TEAMID)` を探し、**秘密鍵が付いている**ことを確認（▶ で開くと
   鍵が見える）→ 証明書を右クリック → 「書き出す…」→ 形式は **個人情報交換 (.p12)** →
   パスワードを決める。このパスワードが `APPLE_DEVELOPER_ID_P12_PASSWORD` になります。
3. **Base64 にする。** `base64 -i DeveloperID.p12 | pbcopy`（クリップボードに入ります）。
4. **App 用パスワードを作る。** appleid.apple.com → サインインとセキュリティ → App 用パスワード →
   「+」→ 名前は `alive-for-mac notarytool` など → 表示された `xxxx-xxxx-xxxx-xxxx` を控える。
   （Apple ID のログインパスワードは使いません。）
5. **Team ID を確認する。** developer.apple.com/account → Membership details → **Team ID**（英数字 10 桁）。
   証明書名の括弧の中も同じ値です。
6. **GitHub にシークレットを 5 つ登録する。** リポジトリ → Settings → Secrets and variables → Actions →
   New repository secret で、次の名前と値を 1 つずつ。

   | シークレット名 | 値 |
   | --- | --- |
   | `APPLE_DEVELOPER_ID_P12` | 手順 3 の Base64 文字列（.p12 の中身） |
   | `APPLE_DEVELOPER_ID_P12_PASSWORD` | 手順 2 で決めた .p12 のパスワード |
   | `APPLE_NOTARY_APPLE_ID` | Apple Developer に登録している Apple ID（メールアドレス） |
   | `APPLE_NOTARY_PASSWORD` | 手順 4 の App 用パスワード |
   | `APPLE_TEAM_ID` | 手順 5 の Team ID |

   ターミナルから登録する場合（`gh` にログイン済み）:

   ```sh
   base64 -i DeveloperID.p12 | gh secret set APPLE_DEVELOPER_ID_P12 -R bassmicrobe/alive-for-mac
   gh secret set APPLE_DEVELOPER_ID_P12_PASSWORD -R bassmicrobe/alive-for-mac   # 入力を求められます
   gh secret set APPLE_NOTARY_APPLE_ID -R bassmicrobe/alive-for-mac
   gh secret set APPLE_NOTARY_PASSWORD -R bassmicrobe/alive-for-mac
   gh secret set APPLE_TEAM_ID -R bassmicrobe/alive-for-mac
   ```

7. 登録できたら、ディスク上の `.p12` を削除します（パスワードマネージャーなどに保管）。

シークレットは `release` ジョブ（タグの push または手動実行）でだけ使われます。pull request の
ビルドやテストには渡りません。リポジトリに書き込める人は、手動実行でも公証済みリリースを作れる点
に注意してください（必要なら GitHub の Environment とレビュー必須設定で絞れます）。

### 2. CI で起きること

1. `Decide signing mode`: 5 つのシークレットがそろっているかを調べる（全部無ければ警告で ad-hoc、
   一部だけ無ければエラーで失敗）。
2. `Import Developer ID certificate`: 使い捨てキーチェーンを作って .p12 を取り込み、署名用の
   identity 名（`Developer ID Application: 名前 (TEAMID)`）を証明書から取り出す。続けて
   `xcrun notarytool store-credentials alive-ci-notary … --keychain <使い捨てキーチェーン>` で
   公証の資格情報を同じキーチェーンに保存する（Apple に資格情報を確認してもらうので、間違いはビルド
   の前に分かる）。`ci-signing.py` はパスワードを標準入力または echo を無効にした端末へ渡し、
   コマンド引数に含めません。`build-app.sh` には `ALIVE_NOTARY_KEYCHAIN_PROFILE=alive-ci-notary` と
   `ALIVE_NOTARY_KEYCHAIN=<キーチェーンのパス>` だけを渡します。
3. `scripts/build-app.sh --zip --dmg --notarize`（下の「build-app.sh の手順」）。`--zip`、`--dmg`、
   `--notarize` を付けたときは、ユニバーサルビルドに失敗しても実行環境のアーキテクチャだけの
   ビルドにはフォールバックせず、失敗終了します。
4. `Verify universal app and signature`: arm64 と x86_64 の両方が入っていること、署名が壊れていないこと。
5. `Verify Developer ID signature and notarization`: `codesign -dvv` の Authority が Developer ID、
   ハードランタイム、`spctl`（`source=Notarized Developer ID`）、`stapler validate`（アプリと DMG）。
6. `Publish GitHub Release`（既存のリリースへ署名なしで上書きするのは、上の `allow_adhoc_overwrite`
   を付けたときだけ）。
7. `Delete signing keychain`: 成功しても失敗してもキーチェーンを消す（`if: always()`）。公証の資格情報
   のプロファイルもこのキーチェーンごと消えます。

`release` ジョブのチェックアウトは `fetch-depth: 0`（全履歴）です。ビルド番号（`CFBundleVersion`）は
`git rev-list --count HEAD` で、浅いクローンだと 1 になってしまうためです。タグの push で動いた
実行は、あとから同じタグの実行が来ても中断されません（`cancel-in-progress` はタグでは false）。

### 3. build-app.sh の手順

`ALIVE_SIGN_IDENTITY` が**無い**と、従来どおり ad-hoc 署名（ハードランタイムなし）です。ある場合:

1. 2 つの appex（`AliveQuickLook`、`AliveWidget`）を、それぞれの entitlements を保ったまま
   `--options runtime --timestamp` で署名 → 次にアプリを署名（`--deep` は使いません。appex の
   entitlements が消えるため）。署名直後に、appex のサンドボックス entitlement とウィジェットの
   読み取り例外が残っているか、Authority と ハードランタイムフラグがあるかを確認します。
2. アプリを `ditto -c -k --keepParent` で一時 zip にする。
3. `xcrun notarytool submit <zip> --wait`（**1 回目の提出**）。結果が `Accepted` 以外なら
   `notarytool log <id>` を表示して失敗終了します。
4. `xcrun stapler staple` をアプリに。
5. **staple 済みの**アプリから配布用 zip を作る。
6. staple 済みのアプリから DMG を作り、DMG にも Developer ID で署名する（`spctl` は DMG
   自身の署名を見るため）。
7. `notarytool submit <dmg> --wait`（**2 回目の提出**）。
8. `stapler staple` を DMG に。
9. 検証: `spctl -a -vv`（アプリ）、`spctl -a -t open --context context:primary-signature -vv`（DMG）、
   `stapler validate`（アプリ、DMG、配布用 zip の中のアプリ）、`codesign -dvv`。

どれか 1 つでも失敗するとスクリプトは 0 以外で終了し、公証の失敗では `notarytool log` を表示します。

### 4. ローカルで実行する

Developer ID Application 証明書が自分の Mac のキーチェーンにある状態で、`macos/` から:

```sh
security find-identity -v -p codesigning     # identity 名を確認

# 資格情報をキーチェーンに保存して使う（パスワードを引数やシェル履歴に残さない）
xcrun notarytool store-credentials "alive-notary" \
    --apple-id "you@example.com" --team-id "TEAMID"     # App 用パスワードを聞かれる
ALIVE_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
ALIVE_NOTARY_KEYCHAIN_PROFILE=alive-notary \
    scripts/build-app.sh --zip --dmg --notarize

```

- `--notarize` には `ALIVE_SIGN_IDENTITY` が必要です。資格情報が足りないと、ビルドを始める前に終了します。
- プロファイルが既定の検索リストに無いキーチェーンにあるときは、そのパスを `ALIVE_NOTARY_KEYCHAIN`
  で渡します（CI がこの形）。
- 署名だけ試すなら `ALIVE_SIGN_IDENTITY=… scripts/build-app.sh`（`--notarize` なし）。
- 1 回の待ちの上限は `ALIVE_NOTARY_TIMEOUT`（既定 `60m`）。公証は通常数分で終わります。
- 署名には Apple のタイムスタンプサーバーへの接続が必要です。

### 5. 手で確認する

```sh
APP="macos/build/Alive for Mac.app"; DMG=macos/dist/AliveForMac-<version>.dmg
spctl -a -vv "$APP"                                              # accepted / source=Notarized Developer ID
spctl -a -t open --context context:primary-signature -vv "$DMG"  # accepted / source=Notarized Developer ID
xcrun stapler validate "$APP"                                    # The validate action worked!
xcrun stapler validate "$DMG"
codesign -dvv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|flags'   # Authority=Developer ID Application: …, flags=…(runtime)
codesign -d --entitlements - "$APP/Contents/PlugIns/AliveWidget.appex"  # sandbox と読み取り例外が残っている
```

実際の利用者の流れを確かめるには、ダウンロードした DMG（隔離属性付き）を別の Mac で開き、
Applications にコピーして起動します。警告が出ず、「このまま開く」も要らないはずです。

### 6. ハードランタイムと entitlements

公証にはハードランタイムが必要です。ハードランタイムでは、他の Team ID で署名されたコードを
同じプロセスに読み込むには `com.apple.security.cs.disable-library-validation` が要ります。
Alive for Mac がサードパーティのコードをプロセス内に読み込むかを調べました（`macos/` で）:

```sh
grep -rnE 'dlopen|dlsym|Bundle\((url|path):|\.load\(\)|CFBundleLoad|CFPlugIn|NSClassFromString|principalClass|AudioComponent|AVAudioUnit|AUAudioUnit|NSBundle' Sources Package.swift
```

ヒットは 6 行だけで、どれもコードの読み込みではありません:

- `AliveWidget.swift` の `Self.load()` と `SpotlightIndexer.swift` の `file.load()` は、自前の
  JSON ファイルを読む関数。
- `LiveLauncher.swift` の `Bundle(url:)?.infoDictionary` は、Live.app の `Info.plist` を読むだけ
  （`Bundle.load()` は呼びません）。
- `PluginBundleReader.swift` の `AudioComponents` は、プラグインの `Info.plist` のキー名。
  旧式の `.rsrc` も、バイト列として解析するだけです（`LegacyComponentResource`）。

プラグイン（VST/AU など）は Info.plist とファイル名を読むだけで、**ロードしません**。Live は
`NSWorkspace` で起動するだけで、再生は `AVAudioPlayer`（Apple のコーデックのみ）、外部コマンドは
`/usr/bin/pluginkit` と `/usr/bin/ditto` だけです。アプリは実行可能メモリ（JIT）も Apple Events
も使いません（`mmap` は `PROT_READ | PROT_WRITE` のみ）。

**結論: `disable-library-validation` も他のハードランタイム用 entitlement も不要です。** アプリ本体は
entitlements なしで署名します（今までと同じ）。appex の entitlements
（`Resources/Extensions/quicklook.entitlements`、`widget.entitlements`。サンドボックス、ウィジェットは
`widget/` フォルダの読み取り例外つき）は署名後もそのまま残り、ビルド中に確認されます。
Sandbox の temporary-exception は公証の妨げになりません（制限されるのは App Store の審査だけ）。

将来、アプリがサードパーティのコードをプロセス内に読み込むようになったら、読み込む側のターゲット
**だけ**に `com.apple.security.cs.disable-library-validation` を持つ entitlements ファイルを作り
（例: `Resources/AliveForMac.entitlements`）、`build-app.sh` の `sign_code "$APP"` にそのファイルを渡し、
この節を更新してください。

### 7. うまくいかないとき

- **公証が Invalid になった:** ジョブのログに `notarytool log` の JSON が出ます（`issues` に原因）。
  手元なら `xcrun notarytool log <submission-id> --keychain-profile alive-notary`。
- **`No valid 'Developer ID Application' identity`:** .p12 が Developer ID **Application**
  証明書（Installer ではない）で、秘密鍵ごと書き出されているか、`APPLE_TEAM_ID` が証明書の括弧内と
  同じかを確認。証明書の中間証明書（Developer ID - G2）は、Apple の
  [Certificate Authority](https://www.apple.com/certificateauthority/) ページにあります。
- **`stapler staple` が失敗する:** 承認直後はチケットがまだ届かないことがあり、スクリプトは 15 秒おきに
  5 回やり直します。
- **証明書の有効期限:** Developer ID 証明書は 5 年です。期限が切れる前に作り直して .p12 と
  `APPLE_DEVELOPER_ID_P12*` を更新してください。期限前に署名・公証したアプリは、期限後も開けます。
- **シークレットを入れ替えたい:** 同じ名前で登録し直すだけです。

---

## English

Pushing a tag `v<version>` (the same number as `macos/VERSION`) makes the `release` job in
`.github/workflows/macos-ci.yml` build `AliveForMac-<version>.zip` and `.dmg` and attach them to a
GitHub Release.

- **With the Apple credentials (the five secrets below) registered:** the build is signed with a
  Developer ID Application certificate, submitted to Apple for notarization, and the tickets are
  stapled to the app and the DMG. Users open it without any Gatekeeper steps.
- **With none of them:** the build is ad-hoc signed as before. The workflow prints
  `::warning::Release is ad-hoc signed and not notarized (missing secrets: …)`, and only when it
  creates the release it puts a "not notarized, use Open Anyway" note (Japanese and English) at the top
  of the release body. Uploading into an existing release leaves its body alone.
- **With some but not all of them (one to four registered):** this is taken for a mistake in the
  secrets. `Decide signing mode` prints an `::error::` and the job fails; no ad-hoc build is made.
- **An ad-hoc build never replaces the files of an existing release by itself.** Re-running a tag
  without the secrets would otherwise put ad-hoc files over notarized ones. When the release exists
  and the build is not signed, `Publish GitHub Release` fails. Only when that is really wanted, run the
  workflow by hand (`workflow_dispatch`) and set the boolean input `allow_adhoc_overwrite` to true
  (default false; always false on a tag push).

### 1. One-time setup

Prerequisite: membership in the Apple Developer Program (paid).

1. **Create the Developer ID Application certificate.**
   - Xcode → Settings → Accounts → select your team → Manage Certificates… → "+" at the bottom left →
     **Developer ID Application**.
   - Or developer.apple.com → Certificates, Identifiers & Profiles → "+" → Developer ID Application
     (upload a CSR made with Keychain Access → Certificate Assistant).
   - Only the Account Holder can create these Developer ID certificates with exportable private keys.
     Cloud-managed certificate permissions are a separate mechanism.
2. **Export a .p12.** Keychain Access → login → My Certificates → find
   `Developer ID Application: Name (TEAMID)` and check that it **has a private key** (expand it with
   the arrow) → right-click the certificate → Export… → format **Personal Information Exchange (.p12)** →
   choose a password. That password is `APPLE_DEVELOPER_ID_P12_PASSWORD`.
3. **Base64-encode it:** `base64 -i DeveloperID.p12 | pbcopy` (copies to the clipboard).
4. **Create an app-specific password.** appleid.apple.com → Sign-In and Security → App-Specific
   Passwords → "+" → a name such as `alive-for-mac notarytool` → note the `xxxx-xxxx-xxxx-xxxx` shown.
   (Never use the Apple ID login password.)
5. **Find the Team ID.** developer.apple.com/account → Membership details → **Team ID** (10
   alphanumeric characters). It is also the value in parentheses in the certificate name.
6. **Register the five secrets on GitHub.** Repository → Settings → Secrets and variables → Actions →
   New repository secret, one per row:

   | Secret name | Value |
   | --- | --- |
   | `APPLE_DEVELOPER_ID_P12` | the Base64 text from step 3 (the contents of the .p12) |
   | `APPLE_DEVELOPER_ID_P12_PASSWORD` | the .p12 password chosen in step 2 |
   | `APPLE_NOTARY_APPLE_ID` | the Apple ID (email) of the Apple Developer account |
   | `APPLE_NOTARY_PASSWORD` | the app-specific password from step 4 |
   | `APPLE_TEAM_ID` | the Team ID from step 5 |

   From a terminal (logged in with `gh`):

   ```sh
   base64 -i DeveloperID.p12 | gh secret set APPLE_DEVELOPER_ID_P12 -R bassmicrobe/alive-for-mac
   gh secret set APPLE_DEVELOPER_ID_P12_PASSWORD -R bassmicrobe/alive-for-mac   # prompts for the value
   gh secret set APPLE_NOTARY_APPLE_ID -R bassmicrobe/alive-for-mac
   gh secret set APPLE_NOTARY_PASSWORD -R bassmicrobe/alive-for-mac
   gh secret set APPLE_TEAM_ID -R bassmicrobe/alive-for-mac
   ```

7. Once registered, delete the `.p12` from disk (keep it in a password manager).

The secrets are only used by the `release` job (tag push or manual run). Pull-request builds and tests
never get them. Note that anyone with write access to the repository can also run the workflow manually
and so produce a notarized release; a GitHub Environment with required reviewers can restrict that.

### 2. What CI does

1. `Decide signing mode`: checks that all five secrets are set (none: a warning and an ad-hoc build;
   some but not all: an error and the job fails).
2. `Import Developer ID certificate`: creates a throw-away keychain, imports the .p12 and reads the
   signing identity name (`Developer ID Application: Name (TEAMID)`) from the certificate. Then
   `xcrun notarytool store-credentials alive-ci-notary … --keychain <throw-away keychain>` saves the
   notarization credentials in the same keychain (Apple checks them at once, so a wrong password shows
   before the build). `ci-signing.py` supplies passwords through stdin or a terminal with echo disabled,
   never through process arguments. `build-app.sh` gets `ALIVE_NOTARY_KEYCHAIN_PROFILE=alive-ci-notary` and
   `ALIVE_NOTARY_KEYCHAIN=<keychain path>`, never the password.
3. `scripts/build-app.sh --zip --dmg --notarize` (next section). With `--zip`, `--dmg` or `--notarize`
   a failed universal build stops the script; it does not fall back to a host-architecture build.
4. `Verify universal app and signature`: both arm64 and x86_64 present, signature intact.
5. `Verify Developer ID signature and notarization`: `codesign -dvv` authority is Developer ID, hardened
   runtime, `spctl` (`source=Notarized Developer ID`), `stapler validate` for the app and the DMG.
6. `Publish GitHub Release` (replacing the files of an existing release with an unsigned build only
   with `allow_adhoc_overwrite`, above).
7. `Delete signing keychain`: removes the keychain whether the job succeeded or not (`if: always()`).
   The notarization profile goes with it.

The `release` job checks out with `fetch-depth: 0` (the whole history): the build number
(`CFBundleVersion`) is `git rev-list --count HEAD`, which a shallow clone turns into 1. A run started by
a tag push is not cancelled by a later run of the same tag (`cancel-in-progress` is false on tags).

### 3. What build-app.sh does

Without `ALIVE_SIGN_IDENTITY` it signs ad-hoc (no hardened runtime), exactly as before. With it:

1. Signs both app extensions (`AliveQuickLook`, `AliveWidget`) with `--options runtime --timestamp`,
   keeping their own entitlements, then signs the app (never `--deep`: it would re-sign the extensions
   without their entitlements). Right after signing it checks that the sandbox entitlement and the
   widget's read exception survived, and that authority and the hardened-runtime flag are present.
2. Zips the app with `ditto -c -k --keepParent` into a temporary file.
3. `xcrun notarytool submit <zip> --wait` (**submission 1**). Anything other than `Accepted` prints
   `notarytool log <id>` and fails.
4. `xcrun stapler staple` the app.
5. Writes the release zip from the **stapled** app.
6. Builds the DMG from the stapled app and signs the DMG with the Developer ID identity too (`spctl`
   judges a disk image by its own signature).
7. `notarytool submit <dmg> --wait` (**submission 2**).
8. `stapler staple` the DMG.
9. Verifies: `spctl -a -vv` (app), `spctl -a -t open --context context:primary-signature -vv` (DMG),
   `stapler validate` (app, DMG and the app inside the release zip), `codesign -dvv`.

Any failure ends the script with a non-zero status; a notarization failure prints `notarytool log` first.

### 4. Running it locally

With the Developer ID Application certificate in your Mac's keychain, from `macos/`:

```sh
security find-identity -v -p codesigning     # shows the identity name

# Store credentials in the keychain (keeps the password out of process arguments and shell history)
xcrun notarytool store-credentials "alive-notary" \
    --apple-id "you@example.com" --team-id "TEAMID"     # asks for the app-specific password
ALIVE_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
ALIVE_NOTARY_KEYCHAIN_PROFILE=alive-notary \
    scripts/build-app.sh --zip --dmg --notarize

```

- `--notarize` requires `ALIVE_SIGN_IDENTITY`; missing credentials stop the script before the build starts.
- When the profile lives in a keychain that is not on the default search list, pass its path as
  `ALIVE_NOTARY_KEYCHAIN` (this is what CI does).
- To try signing only: `ALIVE_SIGN_IDENTITY=… scripts/build-app.sh` (no `--notarize`).
- `ALIVE_NOTARY_TIMEOUT` (default `60m`) caps each wait. Notarization usually takes a few minutes.
- Signing needs a connection to Apple's timestamp server.

### 5. Checking by hand

```sh
APP="macos/build/Alive for Mac.app"; DMG=macos/dist/AliveForMac-<version>.dmg
spctl -a -vv "$APP"                                              # accepted / source=Notarized Developer ID
spctl -a -t open --context context:primary-signature -vv "$DMG"  # accepted / source=Notarized Developer ID
xcrun stapler validate "$APP"                                    # The validate action worked!
xcrun stapler validate "$DMG"
codesign -dvv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|flags'   # Authority=Developer ID Application: …, flags=…(runtime)
codesign -d --entitlements - "$APP/Contents/PlugIns/AliveWidget.appex"  # sandbox and read exception still there
```

To see what a user sees, open the downloaded DMG (it carries the quarantine attribute) on another Mac,
copy the app to Applications and launch it: no warning, and no Open Anyway.

### 6. Hardened runtime and entitlements

Notarization requires the hardened runtime. Under it, loading code signed by another Team ID into the
same process needs `com.apple.security.cs.disable-library-validation`. We checked whether Alive for Mac
loads third-party code in-process (from `macos/`):

```sh
grep -rnE 'dlopen|dlsym|Bundle\((url|path):|\.load\(\)|CFBundleLoad|CFPlugIn|NSClassFromString|principalClass|AudioComponent|AVAudioUnit|AUAudioUnit|NSBundle' Sources Package.swift
```

Only six lines match and none loads code:

- `Self.load()` in `AliveWidget.swift` and `file.load()` in `SpotlightIndexer.swift` are our own
  functions that read a JSON file.
- `Bundle(url:)?.infoDictionary` in `LiveLauncher.swift` only reads Live.app's `Info.plist`
  (`Bundle.load()` is never called).
- `AudioComponents` in `PluginBundleReader.swift` is a key name in a plug-in's `Info.plist`; legacy
  `.rsrc` files are parsed as plain bytes (`LegacyComponentResource`).

Plug-ins (VST/AU, ...) are only inventoried from their Info.plist and file names, never loaded. Live is
started through `NSWorkspace`, playback is `AVAudioPlayer` (Apple codecs only), and the only external
commands are `/usr/bin/pluginkit` and `/usr/bin/ditto`. The app uses no executable memory (JIT) and no
Apple Events (`mmap` is `PROT_READ | PROT_WRITE` only).

**Conclusion: neither `disable-library-validation` nor any other hardened-runtime entitlement is
needed.** The app itself is signed without entitlements (as before). The extensions keep their
entitlements (`Resources/Extensions/quicklook.entitlements` and `widget.entitlements`: sandbox, plus
the widget's read exception for its `widget/` folder); the build checks that they survive signing.
Sandbox temporary exceptions do not get in the way of notarization (only App Store review restricts
them).

If the app ever loads third-party code in-process, add `com.apple.security.cs.disable-library-validation`
to an entitlements file for **only** the target that loads it (for the app: a new
`Resources/AliveForMac.entitlements`), pass that file to `sign_code "$APP"` in `build-app.sh`, and
update this section.

### 7. Troubleshooting

- **Notarization came back Invalid:** the job log shows the `notarytool log` JSON (see `issues`). By
  hand: `xcrun notarytool log <submission-id> --keychain-profile alive-notary`.
- **`No valid 'Developer ID Application' identity`:** check that the .p12 holds a Developer ID
  **Application** certificate (not Installer) exported together with its private key, and that
  `APPLE_TEAM_ID` equals the value in parentheses in the certificate name. The Developer ID - G2
  intermediate certificate is on Apple's
  [Certificate Authority](https://www.apple.com/certificateauthority/) page.
- **`stapler staple` fails:** right after approval the ticket may not be available yet; the script
  retries five times, 15 seconds apart.
- **Certificate expiry:** a Developer ID certificate lasts five years. Create a new one before it
  expires and update `APPLE_DEVELOPER_ID_P12*`. Apps signed and notarized before expiry keep opening.
- **Replacing a secret:** register it again under the same name.
