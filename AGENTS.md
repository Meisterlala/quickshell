# Agent Notes

- This is a Quickshell v0.3.0 config repository at `~/.config/quickshell`.
- Reference docs: https://quickshell.org/docs/v0.3.0/guide/introduction/
- The active config is `main`; run it with `qs -c main`.
- Use `qmllint main/shell.qml` for a quick QML syntax check before/after edits.
- For Quickshell-specific errors, run `qs -c main` and inspect `qs log -c main`.
- Quickshell live-reloads QML changes when files are saved, so syntax/runtime errors may appear immediately in the running instance and logs.
- Keep imports relative. Do not add `root:/` imports; they can break LSP and singleton behavior.
- Follow the v0.3.0 guide pattern of using `Variants` with `Quickshell.screens` for per-monitor windows.
- Avoid per-screen polling work when a module is hidden. Prefer Quickshell support libraries, such as `SystemClock`, over shelling out where practical.
- Make minimal, focused changes and do not alter unrelated user config files.
