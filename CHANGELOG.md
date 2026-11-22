# Changelog

## [0.2.1] - 2026-11-22

- Edit the title directly above the timer without opening Notes.
- Save title edits automatically before or during a focus session; Enter ends editing.
- Keep the title optional: clearing it restores the Focus placeholder without interrupting the timer.
- Remove the duplicate title field from the notes disclosure.
- Exercise the actual inline text editor and persisted titles in the packaged-app smoke test.

## [0.2.0] - 2026-11-22

- Start focus immediately without entering a task name or notes.
- Run from a persistent menu-bar item showing the remaining time and paused state.
- Replace the large dashboard with a compact timer panel and optional task/notes disclosure.
- Move History to its own window; closing a panel or window no longer quits Hit.
- Keep timer completion and draft saving active independently of visible windows.
- Preserve unsaved edits when the panel closes and warn before quitting with unsaved data.
- Preserve the existing workspace format and all saved sessions.
- Verify the actual menu-bar and Start/Pause/Resume controls in the packaged-app smoke test.

## [0.1.0] - 2026-11-22

- Native macOS window with a 25-minute focus timer and five-minute breaks.
- Task titles and multiline notes, editable while working.
- Pause, resume, manual interval starts, and early finish without losing notes.
- Persistent drafts, running timer state, and readable session history.
- Atomic local JSON storage with visible storage and recovery errors.
- Universal Apple silicon and Intel DMG and ZIP downloads.
- Pull request checks, isolated persistence tests, and packaged-app runtime smoke verification.
