# Hit

A small, native macOS Pomodoro timer that lives in your menu bar. Start a 25-minute focus session immediately, then add a task name or notes whenever you want. Take a five-minute break when you are ready.

- Start in one click, without filling in a form.
- See the countdown and open timer controls from the menu bar.
- Add optional task titles and multiline notes while working.
- Keep the timer running after closing its panel; pause, resume, or finish early.
- Open History separately to read previous sessions and their notes.
- Keep everything on your Mac. No accounts, analytics, servers, or dependencies.

Requires **macOS 13 Ventura or later**, on Apple silicon or Intel.

## Install

1. Download `Hit-<version>-universal.dmg` from [Releases](https://github.com/sm-th/hit/releases/latest).
2. Open the disk image and drag **Hit** into **Applications**.
3. Open Hit from Applications.

The app is ad-hoc signed, **not Developer ID signed or notarized**. macOS may block the first launch. Only if you trust this download, attempt to open it, then use **System Settings → Privacy & Security → Open Anyway**, and confirm. On older macOS versions, right-click → Open may also be available. Do not disable Gatekeeper globally. Managed Macs may require administrator approval. A ZIP is also provided.

`SHA256SUMS` accompanies every release. To verify a download, place it beside that file and run:

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
```

Checksums detect damaged downloads; they are not a substitute for Developer ID verification.

## Use

Open Hit and click **Start Focus**. No task name or notes are required. The compact panel is available from the timer icon and countdown in the macOS menu bar. Use **Pause** or **Resume** on the same main button.

Expand **Task & notes** whenever you want to name the current session or write a comment. Edits save automatically. The block stays collapsed until you open it; History is a separate window rather than a permanent sidebar.

Click outside the panel to dismiss it. Hit stays in the menu bar, keeps counting down, and records completion even when no panel or window is open. Click its menu-bar item to open it again. Closing History does not quit Hit. Choose **Quit** in the panel to exit the app completely. Hit does not occupy the Dock.

When a focus interval completes, choose **Start Break** or **Skip Break**. Following a break, start the next focus interval immediately. **Finish Early** saves the session and notes in History. Untitled sessions are displayed as **Focus**.

Running timers continue across sleep and explicit app quits using their saved deadlines. A paused timer stays paused. Reopening Hit after a deadline records one completed interval at its original deadline. Next intervals always start manually; there is no unattended chain of sessions. Durations are fixed at 25/5 minutes. This version has no background notifications or alarm sound; the menu-bar countdown shows the current phase.

## Local data

The complete workspace lives in:

```text
~/Library/Application Support/Hit/workspace.json
```

This readable JSON contains drafts, the current timer, task notes, and session history. Use the folder button in the panel to reveal it. It is created on the first edit or timer action. Saves replace the file atomically before the app reports success. Save failures remain visible, and unsaved text stays in memory even when the panel is dismissed. Use **Retry Saving** after resolving the storage problem. Hit warns before quitting with unsaved changes. The workspace format is unchanged from 0.1.0; existing sessions and history are preserved.

To back up or restore, **quit Hit first**, then copy or replace this file. Notes are ordinary unencrypted local files, protected by your Mac account and disk security; do not store secrets. Hit makes no automatic backups and has no cloud sync or history deletion in this version. Corrupt or unsupported workspace files produce a recovery screen and are never silently replaced. Back up the original before repairing it or moving it aside to start fresh.

## Development

Install Xcode 15 or later (or its command-line tools) on macOS:

```sh
swift test
swift run Hit
bash scripts/build-app.sh 0.2.0
open dist/Hit.app
```

The package uses Swift 5.9 language tools and system frameworks only. `Sources/HitCore` owns durable timer transitions and persistence; `Sources/Hit` owns the SwiftUI interface. Tests use isolated temporary workspaces and explicit times, without sleeps. They cover saved drafts and notes, relaunch, pause/resume, completion after absence, stopped sessions, invalid transitions, and storage failures.

The packaging script builds one universal executable for arm64 and x86_64, creates an ad-hoc signed app, and writes DMG, ZIP, and checksums to `dist/`. It requires the full macOS SDK and Apple's `lipo`, `codesign`, and `hdiutil` tools.

## Contributing and releases

1. Create a branch and open a pull request against `main`.
2. Describe behavior, data compatibility, and verification in the PR template. Keep source, UI, and documentation in English.
3. The **Verify and package** check runs tests, builds the universal app, and exercises its actual menu-bar and Start/Pause/Resume buttons in an isolated workspace. CI uploads installers and screenshots of the compact panel and expanded notes.
4. Merge after checks pass. Update `CHANGELOG.md`, then push an annotated `vX.Y.Z` tag on `main`.
5. The same workflow rechecks that tagged commit and publishes its installers to GitHub Releases. The tag must match the changelog version. Release permissions are limited to the publication job.

For example:

```sh
git tag -a v0.2.0 -m "Hit 0.2.0"
git push origin v0.2.0
```

The app's `--smoke-test` mode is for CI: it clicks the real menu-bar button and native timer control, verifies title-free start, pause/resume, countdown with the panel closed, and persistence of optional task notes, then exits. Set `HIT_SMOKE_SCREENSHOT` to capture the compact panel and expanded notes. It never reads or writes your normal workspace.

## License

[MIT](LICENSE).
