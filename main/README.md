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
qs ipc -c main call bar togglePopup calendar
```

`refreshModule all` reaches every enabled script-backed module and refreshes
calendars only while open. Individual names include `audio`, `cpu`, `gpu`,
`memory`, `codex-usage`, `llama-models`, `k8s-alerts`, `fritz-traffic`, `habits`,
`updates`, `systemd-failed-units`, and `calendar`. Running requests finish rather
than being cancelled by the next poll.

`togglePopup` accepts `calendar`, `habits`, `k8s-alerts`, and `notifications`; unknown names return
`false`. Calendar IPC targets the focused monitor. Habits IPC restores the module
from alternative mode. Habit changes are queued, and failed changes remain visible.
Audio left/right clicks launch detached `pwvucontrol`/`helvum`; middle-click
mutes/unmutes and refreshes the indicator.

This config intentionally does not modify Hyprland autostart yet. Keep `waybar.service` enabled until the Quickshell bar has been tested.

## Clock calendar

Hover the clock to open the calendar; moving into the popup keeps it open.
Click the clock to pin/unpin it. It does not grab keyboard focus. The arrows
change the displayed month, and **Today** returns to the current month.
Dots mark dates with events or dated tasks. Click a day to show only events
and dated tasks overlapping that date, including past events. Click the selected
day again to clear the selection and restore the next 30 days (up to 100
occurrences). Browsing other months keeps the selected date and its events.

The month grid is adapted from [Nebula Shell](https://github.com/Linuxury/nebula-shell/blob/main/components/bar/Clock.qml)
under its [MIT license](licenses/nebula-shell-MIT.txt).

`main/scripts/thunderbird_calendar.py` requires `python-dateutil` and reads the
default Thunderbird profile's `calendar-data/local.sqlite` and `cache.sqlite`.
Enable **Offline Support** in Thunderbird's calendar properties for synced
calendars. Thunderbird remains responsible for syncing; the helper never reads
credentials, contacts remote servers, or writes to the profile. It reads private
temporary snapshots including SQLite's WAL, so Thunderbird can stay open.
Recurrences, exceptions, all-day dates, timezones and incomplete dated tasks are
supported. Uncached ICS files/feeds are not read directly. **Sleep as Android**
is excluded from both the agenda and date markers (see `EXCLUDED_CALENDARS` in
the helper). Disabled calendars and cancelled/deleted/completed items are omitted.

Data refreshes on opening, changing the month, and once per minute while open.
No calendar process or polling timer runs while the popup is closed. QML changes
auto-reload: use `qmllint main/shell.qml` and `qs log -c main` for validation;
do not launch a second instance.

## Notifications

Quickshell owns `org.freedesktop.Notifications` directly; SwayNC is not needed.
The service and card separation is inspired by [Omarchy 4](https://github.com/omacom/omarchy/tree/v4.0.6/shell/plugins/notifications),
with presentation matching this config rather than importing Omarchy's shell.

Popups appear on the focused display. The center fits its content and scrolls
when it reaches the available screen height. A compact row provides DND, sleep
inhibition, the second-monitor DPMS toggle, and clear-all, without a title or Close
button. Escape, focus loss, and Super+X close it. Normal on-demand focus replaces
global input grabs, so clicks outside reach the underlying app. The background
context menu also retains these controls. Media controls use native MPRIS
subscriptions. System controls are queried only while the center is open.

Normal/low popups default to 10/5 seconds. Explicit timeouts are honored, zero
and critical notifications stay until dismissed, and hover/reply input pauses
expiry. Swipe a card left or right to dismiss it; short drags spring back. Icons
and notification images occupy the right side of the card. DND suppresses ordinary
popups but retains their history; critical alerts
bypass it. Transient notifications are never saved. Live notification actions
and inline replies remain available after a popup leaves the screen.

The latest 100 non-transient notifications and DND preference are saved under
`$XDG_STATE_HOME/quickshell/notifications.json` (default
`~/.local/state/quickshell/notifications.json`) in a private directory. Full shell
restarts restore text history, not dead actions or temporary images. QML live
reloads retain live notifications and their actions.

```sh
qs ipc -c main call notifications toggle
qs ipc -c main call notifications setDnd true
qs ipc -c main call notifications setDnd false
qs ipc -c main call notifications clear
qs ipc -c main call notifications getState
```

The user D-Bus activation file points to `quickshell-main.service`, which is
already started by Hyprland. GameMode uses the DND IPC calls. Hyprland excludes
`quickshell-notifications` and `quickshell-notification-center` from screen sharing.
Both protected surfaces are bounded to their content. A full-screen transparent
surface would black out the entire shared display; an input mask does not limit
screen-sharing exclusion. Dismissal observes normal window focus loss; it must
not use `HyprlandFocusGrab`, exclusive keyboard focus, or a full-screen input veil.
Temporary validation belongs in `/tmp`, not in this repository.
