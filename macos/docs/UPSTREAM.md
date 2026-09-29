# Taking in an upstream update / 上流アップデートの取り込み方

English first, 日本語は後半にあります。

---

## English

Alive for Mac is a Swift rewrite of [rueblose/alive](https://github.com/rueblose/alive) (Windows,
C#). The port never edits upstream files (`src/`, `nebula/`, ...), so merging upstream is always
conflict-free. The real work is porting each upstream C# change to the matching Swift file. Three
things drive that work:

- `macos/UPSTREAM_SYNC` — the last upstream commit that has been ported.
- `macos/upstream-map.tsv` — upstream file -> Swift file(s), owner, notes. `-` means "no port needed".
- `macos/scripts/upstream-sync.sh` — merges upstream and prints the porting report.

### 1. Bring the upstream commits in

Either click **Sync fork** on GitHub (bassmicrobe/alive-for-mac -> "Sync fork" -> "Update branch")
and `git pull`, or run the script from a clean working tree:

```sh
macos/scripts/upstream-sync.sh              # fetch, merge upstream/main, print the report
macos/scripts/upstream-sync.sh --report-only  # report only, no merge
macos/scripts/upstream-sync.sh --since <sha>  # report from another commit (catching up)
macos/scripts/upstream-sync.sh --markdown     # same report as GitHub markdown
```

If the merge ever conflicts, the script aborts it and explains: it means an upstream file was
edited on this branch. Restore upstream's version and retry.

### 2. Read the report

For each upstream commit (oldest first) you get the touched files and where they land:

```
0493e5b  2026-09-22  Версия 1.1
  M src/app.manifest
      -> Sources/.../build-app.sh  [owner 1A]  (Info.plist equivalent)
  M tools/Shot.cs
      -> no port needed (Windows test harnesses; ...)
  M docs/img/settings.png
      -> UNMAPPED — add a row to upstream-map.tsv
```

- **mapped** — port the change into the listed Swift file(s).
- **no port needed** — the map says why (Windows-only, docs, ...). Skip, but sanity-check the reason.
- **UNMAPPED** — a new upstream file. Decide which Swift file ports it (or `-` with a reason) and
  add a row to `upstream-map.tsv` first.

The last section, "Swift files to update", is your deduplicated checklist.

### 3. Port each change

Work commit by commit. Open the upstream diff (`git show <sha> -- <file>`), find the Swift target in
the map, and apply the same behaviour change. Rules from `PORTING.md` still hold: never edit
upstream files; keep `FORMAT.md` semantics; every visible string goes through the en/ja string
tables. If upstream added or renamed a file, add or fix its row in `upstream-map.tsv`. If a change is
intentionally skipped, record it in `macos/PARITY.md`.

### 4. Test

```sh
cd macos && swift build && swift test
```

Add or update tests for the ported behaviour (fixtures are generated in code, see `PORTING.md` §10).

### 5. Mark and commit

```sh
macos/scripts/upstream-sync.sh --mark        # writes upstream/main SHA into macos/UPSTREAM_SYNC
git add macos
git commit -m "feat(mac): port upstream <old>..<new>"
```

`--mark <sha>` records a specific commit instead (use it if you ported only part of the range).
The weekly workflow `upstream-watch.yml` opens/updates an issue labelled `upstream-sync` while
commits remain unported, and closes it once `UPSTREAM_SYNC` catches up.

### Prompt for Claude Code

Paste this into Claude Code at the repo root:

```text
Take in the latest upstream (rueblose/alive) changes for Alive for Mac. Follow macos/docs/UPSTREAM.md
and macos/docs/PORTING.md exactly.

1. Work on a fresh branch from macos-port with a clean tree. Run
   `macos/scripts/upstream-sync.sh` (fetch + merge upstream/main + report). If it says
   "Up to date", stop.
2. For every upstream commit in the report, read the diff (`git show <sha>`), and port it to the
   Swift files the report lists (via macos/upstream-map.tsv). Never edit upstream-owned files.
   Localize new user-visible strings in both English and Japanese.
3. For every UNMAPPED file, decide its Swift target (or `-` with a reason) and add a row to
   macos/upstream-map.tsv. Fix rows for renamed files. Record deliberately skipped behaviour in
   macos/PARITY.md.
4. Add or update XCTest tests for the ported behaviour. Run `cd macos && swift build && swift test`
   until green with no new warnings.
5. Run `macos/scripts/upstream-sync.sh --mark`, then commit in small conventional commits
   (`feat(mac): ...`, `fix(mac): ...`, final `chore(mac): mark upstream <sha> as ported`).
   No attribution trailers. Do not push.
6. Report: the commits ported, files changed, anything skipped and why, test results.
```

---

## 日本語

Alive for Mac は [rueblose/alive](https://github.com/rueblose/alive)（Windows / C#）の Swift 書き直し版です。
移植側は上流のファイル（`src/`、`nebula/` など）を一切編集しないので、上流のマージは常にコンフリクトなしで
できます。実際の作業は、上流の C# の変更を対応する Swift ファイルへ移植することです。次の 3 つが土台です。

- `macos/UPSTREAM_SYNC` — 移植済みの最後の上流コミット。
- `macos/upstream-map.tsv` — 上流ファイル -> Swift ファイル、担当、備考。`-` は「移植不要」。
- `macos/scripts/upstream-sync.sh` — 上流をマージし、移植レポートを出力します。

### 1. 上流コミットを取り込む

GitHub の **Sync fork**（bassmicrobe/alive-for-mac の「Sync fork」->「Update branch」）を押してから
`git pull` するか、作業ツリーがクリーンな状態でスクリプトを実行します。

```sh
macos/scripts/upstream-sync.sh              # fetch、upstream/main をマージ、レポート出力
macos/scripts/upstream-sync.sh --report-only  # マージせずレポートのみ
macos/scripts/upstream-sync.sh --since <sha>  # 別のコミットからのレポート（遅れを取り戻すとき）
macos/scripts/upstream-sync.sh --markdown     # 同じレポートを GitHub 用 markdown で出力
```

マージがコンフリクトした場合、スクリプトはマージを中止して理由を表示します。このブランチで上流ファイルを
編集してしまったという意味なので、上流の版に戻してからやり直してください。

### 2. レポートを読む

上流コミットごと（古い順）に、変更されたファイルと移植先が表示されます。

- **mapped** — 表示された Swift ファイルに変更を移植します。
- **no port needed** — 理由がマップに書かれています（Windows 専用、ドキュメントなど）。基本はスキップですが、理由は確認してください。
- **UNMAPPED** — 上流の新規ファイル。まず移植先の Swift ファイル（または理由付きの `-`）を決めて
  `upstream-map.tsv` に行を追加します。

末尾の「Swift files to update」が、重複を除いたチェックリストです。

### 3. 変更を 1 件ずつ移植する

コミット単位で作業します。上流の差分（`git show <sha> -- <file>`）を読み、マップで移植先を探し、同じ挙動の変更を
適用します。`PORTING.md` のルールは引き続き有効です。上流ファイルは編集しない、`FORMAT.md` の仕様を守る、
表示文字列は必ず英語/日本語の文字列テーブル経由にする。上流でファイルが追加・改名された場合は
`upstream-map.tsv` の行を追加・修正します。意図的に見送る変更は `macos/PARITY.md` に記録します。

### 4. テスト

```sh
cd macos && swift build && swift test
```

移植した挙動のテストを追加・更新します（フィクスチャはコードで生成。`PORTING.md` §10 参照）。

### 5. マークしてコミット

```sh
macos/scripts/upstream-sync.sh --mark        # upstream/main の SHA を macos/UPSTREAM_SYNC に書き込む
git add macos
git commit -m "feat(mac): port upstream <old>..<new>"
```

範囲の一部だけ移植した場合は `--mark <sha>` でそのコミットを指定します。週次ワークフロー
`upstream-watch.yml` は、未移植コミットがある間 `upstream-sync` ラベルの issue を作成・更新し、
`UPSTREAM_SYNC` が追いつくと自動で閉じます。

### Claude Code 用プロンプト

リポジトリのルートで Claude Code に次をそのまま貼り付けてください。

```text
Alive for Mac に、上流 (rueblose/alive) の最新の変更を取り込んでください。
macos/docs/UPSTREAM.md と macos/docs/PORTING.md に厳密に従うこと。

1. クリーンな作業ツリーで macos-port から新しいブランチを切り、
   `macos/scripts/upstream-sync.sh`（fetch + upstream/main のマージ + レポート）を実行。
   "Up to date" と出たら終了。
2. レポートの各上流コミットについて差分 (`git show <sha>`) を読み、レポートに出た Swift ファイル
   （macos/upstream-map.tsv 経由）へ移植する。上流のファイルは編集しない。新しい表示文字列は
   英語と日本語の両方をローカライズする。
3. UNMAPPED のファイルは移植先の Swift ファイル（または理由付きの `-`）を決めて
   macos/upstream-map.tsv に行を追加。改名されたファイルの行も直す。意図的に見送った挙動は
   macos/PARITY.md に記録する。
4. 移植した挙動の XCTest を追加・更新。`cd macos && swift build && swift test` が
   新しい警告なしで通るまで繰り返す。
5. `macos/scripts/upstream-sync.sh --mark` を実行し、小さな conventional commit
   （`feat(mac): ...`、`fix(mac): ...`、最後に `chore(mac): mark upstream <sha> as ported`）でコミット。
   Co-Authored-By などの署名は付けない。push しない。
6. 報告: 移植したコミット、変更したファイル、見送った内容と理由、テスト結果。
```
