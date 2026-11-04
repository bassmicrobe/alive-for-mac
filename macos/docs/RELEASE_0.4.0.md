# Alive for Mac 0.4.0

2026-11-04 — オリジナル 1.3.1〜1.3.3 の取り込み、公証、全体監査

- **オリジナル（Alive 1.3.1〜1.3.3）の変更をすべて取り込み。** Windows 専用の部分（画面の DPI 対応、独自のスムーズスクロール、Windows 11 のメニューの角）を除き、Mac 版に移植しました。差分は [PARITY.md](../PARITY.md) にあります。
- **画面の拡大縮小。** 設定 → 外観で 75 / 100 / 125% を選ぶと、その場で文字と部品の大きさが変わります。
- **作業カレンダーの日をクリック。** その日に保存したプロジェクトが一覧され、選ぶとタイルへ移動します。作業履歴（`activity.cache`）は保存ごとのプロジェクトも記録します。以前の版でもそのまま読めます。
- **フィルターのカレンダー。** 空の欄で開くと日付は未選択。矢印で日・週、Page Up / Down で月、Return で決定。
- **検索をホームとセット一覧で統一。** 名前・フォルダ・プラグイン・レンダー名・タグ・メモを対象に、空白で区切った語をすべて含むものを表示します（全角・半角を区別しません）。
- **セット一覧と詳細。** 同じ日に保存したバージョンには時刻を表示。インスペクタの「copy list」でプラグイン一覧（インストール済み／不足、名前・バージョン・形式・メーカー）をコピー。行メニューに「パスをコピー」。ピン留めが無いときは星を隠します。`Home` / `End`、検索欄から `↓` で結果へ。
- **アレンジメントのプレビュー。** トラック名付き、クリップ名なし。トラックは名前より低くならず、多いときはスクロール。操作は Live と同じ（ホイール、`⇧` / `⌘` / `⌥` + ホイール、中ボタンのドラッグ、ピンチ）。小節はセットの拍子で数えます。
- **プレーヤー。** `⇧Return` でレンダーを Finder に表示。読み込み途中や壊れた音声ファイルでも波形の表示が止まらず、`alive.log` に記録します。
- **サンプルの試聴。** 波形の下に試聴の音量スライダー（レンダーの音量とは別、設定に保存）。`→` で選択中のサンプルを頭から再生、空いた場所のクリックで停止。起動時のサンプルフォルダの読み直しは、前回から 1 日以上経ったとき、またはフォルダが増えたときだけ。
- **設定ファイルの保護。** 各 `.cfg` は保存のたびに前の版を `.bak` として残します（文字コードの違うファイルの元のデータは `.orig` に退避）。読めなかったファイルを空の内容で上書きせず、起動時に知らせます。
- **スキャン中のフォルダ追加。** 実行中のスキャンを止めず、終わった直後に追加分を読みます。
- **公証。** リリースは Developer ID で署名し、Apple の公証を受けています。初回起動の「このまま開く」は不要になりました。手順は [RELEASING.md](RELEASING.md)。
- **全体監査。** Codex と各レビュアーによる監査で見つかった問題を修正しました。詳細は[監査レポート](AUDIT_2026-11-04.md)。

**配布:** `AliveForMac-0.4.0.dmg` / `.zip`。macOS 14 以降、Apple Silicon・Intel 両対応。Developer ID 署名・公証済み。既存の設定・カタログ形式を維持し、0.3.2 に戻しても失われるものはありません（新しいキー `uiscale`・`previewvolume` と、キャッシュ末尾の追加情報は、古い版では無視されます）。以前に作られたサムネイルは、セットを保存し直すまで古い小節線のままです。

---

## English

Upstream Alive 1.3.1–1.3.3, notarization, and a full audit:

- **Upstream 1.3.1–1.3.3 ported in full**, except the Windows-only parts (screen DPI handling, the custom smooth scrolling, Windows 11 menu corners); see [PARITY.md](../PARITY.md).
- **Interface scale:** Settings → Appearance, 75 / 100 / 125 %, applied at once.
- **Click a day in the activity calendar** to list the projects saved on it and jump to one. `activity.cache` now records the project of each save; older versions still read it.
- **Filters calendar:** an empty field opens with no day picked; arrows move by day and week, Page Up / Down by month, Return picks.
- **One search rule for Home and Sets:** name, folder, plugins, render names, tags and note; every space-separated word must match (width-insensitive).
- **Sets and inspector:** same-day versions show the time; "copy list" copies the set's plugins (installed / missing; name, version, format, developer); "Copy path" in the row menu; the star hides while nothing is pinned; `Home` / `End`; `↓` from the search field into the results.
- **Arrangement preview:** track names, no clip captions, tracks never lower than their name (scrolls when there are many), Live-like navigation (wheel, `⇧` / `⌘` / `⌥` + wheel, middle-button drag, pinch); bars in the set's time signature.
- **Player:** `⇧Return` shows the render in Finder; a busy or truncated audio file no longer stops the waveform and is logged.
- **Sample audition:** a volume slider under the wave (separate from the render player, saved); `→` plays the selected sample from the start; a click on empty space stops it. Sample folders are re-read at launch only when the last walk is a day old or a folder was added.
- **Config safety:** every `.cfg` save keeps the previous version as `.bak` (the original of a file in another encoding is kept as `.orig`); a file that could not be read is never overwritten with an empty one, and launch says so.
- **Adding a folder during a scan** no longer cancels it; the new folder is scanned right after.
- **Notarization:** releases are Developer ID signed and notarized by Apple; the first launch no longer needs Open Anyway. See [RELEASING.md](RELEASING.md).
- **Full audit:** issues found by Codex and the reviewer agents are fixed; see the [audit report](AUDIT_2026-11-04.md).

**Downloads:** `AliveForMac-0.4.0.dmg` and `.zip`; macOS 14+, universal Apple Silicon / Intel. Developer ID signed and notarized. Existing settings and catalog formats are preserved, and going back to 0.3.2 loses nothing (the new keys `uiscale` and `previewvolume` and the extra cache tails are ignored by older versions). Thumbnails drawn before the update keep the old bar grid until the set is saved again.

MIT. Both license texts and `NOTICE.md` are included in the app and DMG. This is an unofficial port of Alive by RueBlose; it is not affiliated with the original author or Ableton.
