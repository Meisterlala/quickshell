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

`togglePopup` accepts `calendar`, `habits`, and `k8s-alerts`; unknown names return
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

Tests use synthetic calendars, mocked status backends, and isolated offscreen
Quickshell instances containing copies of the real QML modules. They cover audio
click dispatch, mutation queues, polling, IPC, GPU/CPU readings, service failures,
update failures, and Codex deadlines. No desktop interaction, real service
restarts, audio changes, router requests, or account requests occur:

```sh
python3 -m unittest discover -s tests -v
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml -o -,txt
```
