# Audio Unit Rescue: minimum Live validation

Status: **not yet run on Ableton Live**. Record the exact Alive commit, macOS version, Live version, AU name and component version when executing this protocol. CI only checks synthetic sets; it does not run Live.

## Fixture and preparation

1. Use an installed, working third-party AU that appears in Live's browser. In Live, make a small disposable project containing one instance of that AU, a second ordinary device, a short MIDI/audio clip, and a visible automation lane or non-default AU preset. Save it as `AU-Rescue.als` in a dedicated project folder. Avoid an AU that is also loaded on other tracks. Do not use a production project.
2. Close Live completely. Duplicate the entire project folder as a backup outside Alive's indexed roots. Record `shasum -a 256 '/path/to/AU-Rescue Project/AU-Rescue.als'` and list the project folder's files. Keep the hash and backup for comparison. Do not modify, move, or rename the `.component` bundle.
3. Reopen the **original** in Live once to establish the control: the AU and other device load, the clip and automation are present, and the AU makes sound. Close Live without saving. If this control fails, stop: the probe cannot establish that Rescue disabled the AU.
4. Build Alive from the intended commit using `cd macos && swift build && swift test` on a Mac, then use the resulting app (or a locally packaged app). Do **not** invoke `workflow_dispatch`: `macos-ci.yml` publishes or replaces a GitHub Release after packaging on that trigger. Record the commit hash, build result and any skipped tests.

## Probe and observable result

5. In Alive, locate the original set and open **Rescue**. Confirm the chosen plugin appears with format **AU**. Untick only that AU. Keep the other plugins ticked; close Live before pressing **Open probe in Live**. Record the generated path ending in `.alive-probe.als` and the hash of the original again.
6. Watch which exact path Live opens. An expected result is that Live opens the probe, reports the chosen AU as unavailable (or shows a missing-device placeholder), does **not** instantiate the AU, while the other device, clip and automation remain. Record the actual missing-plugin message or screenshot and the relevant section of `~/Library/Preferences/Ableton/Live <version>/Log.txt` (path and timestamps). If no AU warning appears, inspect the device chain and log before declaring success; a log's “loaded” status alone does not prove the AU was skipped.
7. If Alive does not detect Live's result, use **It opened** only after visually verifying the probe path and the device state. Do not turn an absence of log data into a pass. Close Live **without saving** the probe. If Live crashes or the set does not finish loading, record that outcome and use **It didn't open** only when observed.
8. With a successful AU-off probe, click **Save rescued copy** before closing the Rescue sheet. Verify a separate `AU-Rescue (rescued).als` exists. Close the sheet and confirm the probe is gone. Open the saved copy in Live and repeat the AU-missing, other-device, clip and automation observations. Close Live without saving. Compare the original's SHA-256 again. Reopen the original and verify that its AU still loads. The AU bundle should remain at its original path throughout.

## Pass record

Record: original and probe/rescued paths; all three original hashes (before/probe/after); Live, macOS, AU and Alive versions; AU name and format shown by Alive; Live warning, device chain and log observations; whether automatic process/log detection worked or manual answer was required; probe cleanup; original reopened with the AU intact. Mark **pass** only when both the temporary probe and saved copy skip the chosen AU, unaffected devices and automation remain available, and the original and installed AU remain unchanged. Mark any other result **fail or inconclusive**, with the observed step.

This validates the chosen AU/Live combination, not every AU implementation or Live version. Preserve the test project and logs for a repeat run with another AU if needed.
