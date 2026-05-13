# Quickshell Main

First replacement slice for the current Waybar setup.

Run manually after installing Quickshell:

```sh
qs -c main
```

Useful IPC calls:

```sh
qs ipc -c main show
qs ipc -c main call bar refreshModule updates
qs ipc -c main call bar refreshModule all
qs ipc -c main call bar getState
```

This config intentionally does not modify Hyprland autostart yet. Keep `waybar.service` enabled until the Quickshell bar has been tested.
