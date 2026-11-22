# Hit

A small, native macOS Pomodoro timer. Give a task a name, focus for 25 minutes, and jot down notes as you work. Take a five-minute break when you are ready.

- Start, pause, resume, or finish a session early.
- Edit task titles and multiline notes during a focus session.
- Read previous sessions and their notes in History.
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

Enter a task title, optionally add notes, and choose **Start Focus**. Title and note edits save automatically. When the timer completes, the task moves to History; choose **Start Break** or **Skip Break**. Following a break, enter the next task. Select a History item to read its notes. **Finish Early** retains the session rather than deleting it.

Running timers continue while Hit is closed or the Mac sleeps. A paused timer stays paused. Reopening Hit after the deadline records one completed session at its original deadline. Next intervals always start manually; no unattended chains of sessions. The first version has fixed durations, a normal app window, and no background notifications or alarm sound. Keep Hit open to see completion.

## Local data

The complete workspace lives in:

```text
~/Library/Application Support/Hit/workspace.json
```

This readable JSON contains drafts, the current timer, task notes, and session history. Use the folder button in the app to reveal it. It is created on the first edit or timer action. Saves replace the file atomically before the app reports success. A save error stays visible; keep any unsaved text in the window and use **Retry Saving** once the storage problem is resolved. Do not close Hit with unsaved changes.

To back up or restore, **quit Hit first**, then copy or replace this file. Notes are ordinary unencrypted local files, protected by your Mac account and disk security; do not store secrets. Hit makes no automatic backups and has no cloud sync or history deletion in this version. Corrupt or unsupported workspace files produce a recovery screen and are never silently replaced. Back up the original before repairing it or moving it aside to start fresh.

## Development

Install Xcode 15 or later (or its command-line tools) on macOS:

```sh
swift test
swift run Hit
bash scripts/build-app.sh 0.1.0
open dist/Hit.app
```

The package uses Swift 5.9 language tools and system frameworks only. `Sources/HitCore` owns durable timer transitions and persistence; `Sources/Hit` owns the SwiftUI interface. Tests use isolated temporary workspaces and explicit times, without sleeps. They cover saved drafts and notes, relaunch, pause/resume, completion after absence, stopped sessions, invalid transitions, and storage failures.

The packaging script builds one universal executable for arm64 and x86_64, creates an ad-hoc signed app, and writes DMG, ZIP, and checksums to `dist/`. It requires the full macOS SDK and Apple's `lipo`, `codesign`, and `hdiutil` tools.

## Contributing and releases

1. Create a branch and open a pull request against `main`.
2. Describe behavior, data compatibility, and verification in the PR template. Keep source, UI, and documentation in English.
3. The **Verify and package** check runs tests, builds the universal app, and launches that packaged app in an isolated smoke-test workspace. CI uploads installers and a screenshot for inspection.
4. Merge after checks pass. Update `CHANGELOG.md`, then push an annotated `vX.Y.Z` tag on `main`.
5. The same workflow rechecks that tagged commit and publishes its installers to GitHub Releases. The tag must match the changelog version. Release permissions are limited to the publication job.

For the initial release:

```sh
git tag -a v0.1.0 -m "Hit 0.1.0"
git push origin v0.1.0
```

The app's `--smoke-test` mode is for CI: it creates a temporary workspace, exercises real task editing and timer transitions, checks reopening, displays the production window, and exits. Set `HIT_SMOKE_SCREENSHOT` to capture the visible desktop. It never reads or writes your normal workspace.

## License

[MIT](LICENSE).
