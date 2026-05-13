# Quickshell Configs

This repository contains Quickshell configurations under `~/.config/quickshell`.

Quickshell v0.3.0 discovers configs as named directories containing `shell.qml`. The active config here is `main`, so it is launched with:

```sh
qs -c main
```

## Syntax Checks

There is no separate `qs --check` command in Quickshell 0.3.0. The practical checks are:

```sh
qmllint main/shell.qml
```

This catches QML syntax and many static issues, but it may not understand every Quickshell-provided type depending on local Qt/QML import setup.

For the most accurate check, start the config and watch Quickshell's logs:

```sh
qs -c main
qs log -c main
```

Startup/runtime QML errors are reported there. Quickshell live-reloads, so saving a file should also surface syntax errors in the running instance.

## v0.3.0 Patterns

The config follows the v0.3.0 guide patterns:

- `main/shell.qml` is the config entrypoint.
- Imports are relative, not `root:/`, so LSP and singleton behavior stay intact.
- `Bar.qml` uses `Variants` with `Quickshell.screens` so panels are created per monitor and react to monitor changes.
- Per-screen delegates use `required property var modelData` and assign it to `PanelWindow.screen`.
- The clock uses Quickshell's `SystemClock` instead of polling an external `date` process.
- Script-backed modules avoid running timers and commands while their per-screen instance is hidden.
