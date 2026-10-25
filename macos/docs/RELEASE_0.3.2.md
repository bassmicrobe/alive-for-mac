# Alive for Mac 0.3.2

2026-10-25 — 再スキャン・一覧更新の改善と新しいロゴ

- **再スキャンを確実に開始。** フォルダを変更せず「スキャン」を押した場合も再試行します。無効化したフォルダの再選択を正しく保存し、サンプルフォルダ変更時の二重スキャンを防ぎます。
- **プラグイン一覧と移動先を更新。** カタログ更新後に古い行が残る問題を修正し、プラグインへの移動は最新の一覧を使います。
- **サンプル処理の応答性。** 重複判定とフォルダツリー作成でキャンセルを確認します。同じサイズの AIFF を置き換えた場合も、更新日時から再生可否を再確認します。
- **フォルダ不在時の状態表示。** クラウド上のフォルダが Mac に表示されない場合の復旧案内を改善。保持した一覧が古いことを明示し、見つからないフォルダ内のセットを「今すぐ開ける」に数えません。
- **非同期処理の安定性。** 読み込みと進捗通知が完了するまで所有モデルを保持し、解放済みの参照へのアクセスを防ぎます。
- **新しいロゴとアプリアイコン。** 日英 README に明暗テーマ対応ロゴを追加。アプリアイコンは 16〜1024 px の全サイズを収録し、Retina 表示と「情報」画面にも反映します。

**検証:** 直前のローカル監査で 1,009 テスト、失敗 0、条件付きスキップ 11 件。合成データで再スキャン、検索、フォルダ消失・復帰を確認し、新アイコンは実画面で確認しました。詳細は[監査レポート](PERFORMANCE_UIUX_AUDIT_2026-10-25.md)と[ロゴ更新記録](BRANDING_UPDATE_2026-10-25.md)を参照してください。

**配布:** `AliveForMac-0.3.2.dmg` / `.zip`。macOS 14 以降、Apple Silicon・Intel 両対応。ad-hoc 署名、公証なし。既存の設定・カタログ形式を維持します。クラウドフォルダの同期設定は変更しません。

---

## English

Rescan and catalog improvements, with new branding:

- Start a rescan even when folder selections are unchanged, save re-enabled folders correctly, and prevent duplicate sample scans after changing folders.
- Refresh plugin rows when the catalog changes and resolve navigation requests against the latest list.
- Respond to cancellation while grouping duplicates and building sample folder trees. Recheck AIFF playability when a same-size file has a different modification time.
- Clarify recovery when cloud folders are absent from the Mac, keep the stale-catalog notice visible, and exclude sets beneath missing roots from Ready to open.
- Keep catalog owners alive until asynchronous work and progress callbacks finish, preventing access to released references.
- Add theme-aware logos to both READMEs and a complete 16–1024 px app icon set for Retina displays and the About screen.

**Validation:** The preceding local audit completed 1,009 tests with zero failures and 11 conditional skips. Synthetic fixtures covered rescans, search, missing folders and recovery; the new icon was checked in the native UI. See the [audit report](PERFORMANCE_UIUX_AUDIT_2026-10-25.md) and [branding record](BRANDING_UPDATE_2026-10-25.md) for scope.

**Downloads:** `AliveForMac-0.3.2.dmg` and `.zip`; macOS 14+, universal Apple Silicon / Intel. Ad-hoc signed, not notarized. Existing settings and catalog formats are preserved. Cloud synchronization settings are unchanged.

MIT. Both license texts and `NOTICE.md` are included in the app and DMG. This is an unofficial port of Alive by RueBlose; it is not affiliated with the original author or Ableton.
