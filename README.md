# Hit

A small, native macOS Pomodoro timer that lives in your menu bar. Start a 25-minute focus session immediately, then add a task name or notes whenever you want. A five-minute break starts automatically with an unmissable, full-screen countdown.

- Start in one click, without filling in a form.
- See the countdown and open timer controls from the menu bar.
- Add optional task titles and multiline notes while working.
- Keep the timer running after closing its panel; pause, resume, or finish early.
- Get edge-to-edge break windows with a live countdown, plus Minimize and Skip Break.
- Open History separately to read previous sessions and their notes.
- Keep everything on your Mac. No accounts, telemetry, servers, or dependencies.

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

Click **Focus** directly above the timer and type a title, before starting or while working. It saves automatically as you type; press **Enter** to finish editing. Clear it to return to the **Focus** placeholder. Expand **Notes** only when you want to write a comment. No disclosure or extra naming dialog is needed to change the title. History remains in a separate window.

Click outside the panel to dismiss it. Hit stays in the menu bar, keeps counting down, and records completion even when no panel or window is open. Click its menu-bar item to open it again. Closing History does not quit Hit. Choose **Quit** in the panel to exit the app completely. Hit does not occupy the Dock.

When focus completes, Hit saves the task and starts a five-minute break automatically. **Break** appears edge-to-edge over the desktop, including the menu bar and Dock, on connected displays. It shows the countdown and the actual start time. This is an app window, not a Notification Center banner; notification permission is not required.

Choose **Minimize** or press **Escape** to hide the full-screen windows without pausing the break. The countdown continues in the menu bar. Use **Show Break** in the panel to bring the full-screen view back. Pause and resume remain available. **Skip Break**, available on the full-screen view and in the panel, records the skipped break and immediately starts the next focus session.

At the end of a break, a full-screen **Break complete** window shows when it finished. Choose **Start Focus** when you are ready, or minimize it. A normal break completion never starts more work without your action. **Finish Early** still saves a stopped focus session and its notes without starting a break. Untitled sessions appear as **Focus**.

Keep Hit running for full-screen alerts. Running deadlines continue across sleep and explicit app quits; a paused timer stays paused. On wake or reopening, Hit catches up against the original deadlines: one focus and its break, never an unattended chain of focus sessions. If both elapsed while away, it records their actual end times and shows **Break complete**, rather than resetting a fresh five-minute countdown. Restoring a still-active break shows its full-screen view. Previously saved pending breaks remain available to start manually or skip. Durations are fixed at 25/5 minutes.

## Local data

The complete workspace lives in:

```text
~/Library/Application Support/Hit/workspace.json
```

This readable JSON contains drafts, the current timer, task notes, and session history. Use the folder button in the panel to reveal it. It is created on the first edit or timer action. Saves replace the file atomically before the app reports success. Save failures remain visible, and unsaved text stays in memory even when the panel is dismissed. Use **Retry Saving** after resolving the storage problem. Hit warns before quitting with unsaved changes. The workspace format is unchanged from 0.1.0; existing sessions and history are preserved.

### Break records for analytics

Breaks are first-class entries in `history`, using the same schema as focus sessions. Each record has a unique `id`, `kind` (`focus` or `rest`), `startedAt`, `endedAt`, `status`, planned `duration` in seconds, and final `remaining` seconds. Dates use Foundation Codable's seconds since 2001-01-01 00:00:00 UTC. Completed breaks have status `completed`; breaks skipped early have status `stopped` and appear as **Skipped** in History. Even a skipped, previously pending break is recorded, with zero elapsed time.

For archived sessions, `duration - remaining` is active elapsed time, excluding pauses. `endedAt - startedAt` is wall-clock time, including pauses. These values preserve both completed and shortened breaks for future analytics. Finishing focus and starting its break, or skipping a break and starting focus, each saves as one atomic transaction. The store is still the local JSON workspace, not a SQLite database.

To back up or restore, **quit Hit first**, then copy or replace this file. Notes are ordinary unencrypted local files, protected by your Mac account and disk security; do not store secrets. Hit makes no automatic backups and has no cloud sync or history deletion in this version. Corrupt or unsupported workspace files produce a recovery screen and are never silently replaced. Back up the original before repairing it or moving it aside to start fresh.

## Development

Install Xcode 15 or later (or its command-line tools) on macOS:

```sh
swift test
swift run Hit
bash scripts/build-app.sh 0.3.0
open dist/Hit.app
```

The package uses Swift 5.9 language tools and system frameworks only. `Sources/HitCore` owns durable timer transitions and persistence; `Sources/Hit` owns the SwiftUI interface. Tests use isolated temporary workspaces and explicit times, without sleeps. They cover saved drafts and notes, relaunch, pause/resume, completion after absence, stopped sessions, invalid transitions, and storage failures.

The packaging script builds one universal executable for arm64 and x86_64, creates an ad-hoc signed app, and writes DMG, ZIP, and checksums to `dist/`. It requires the full macOS SDK and Apple's `lipo`, `codesign`, and `hdiutil` tools.

## Contributing and releases

1. Create a branch and open a pull request against `main`.
2. Describe behavior, data compatibility, and verification in the PR template. Keep source, UI, and documentation in English.
3. The **Verify and package** check runs tests, builds the universal app, and exercises its actual menu-bar controls, inline title editor, full-screen break transitions, Escape/minimize, Skip Break, and saved history. CI uploads installers and screenshots of the compact panel, notes, full-screen break, and break completion.
4. Merge after checks pass. Update `CHANGELOG.md`, then push an annotated `vX.Y.Z` tag on `main`.
5. The same workflow rechecks that tagged commit and publishes its installers to GitHub Releases. The tag must match the changelog version. Release permissions are limited to the publication job.

For example:

```sh
git tag -a v0.3.0 -m "Hit 0.3.0"
git push origin v0.3.0
```

The app's `--smoke-test` mode uses an isolated temporary workspace. It exercises real controls and text editing, then restores near-deadline sessions through the production journal to let the ordinary application ticker trigger breaks and completion. It verifies full-display window bounds, Escape/minimize without pausing, no repeated foregrounding after dismissal, manual next focus, and Skip Break with persisted outcome and timing. Set `HIT_SMOKE_SCREENSHOT` to capture the actual interface. It never reads or writes your normal workspace.

## License

[MIT](LICENSE).
