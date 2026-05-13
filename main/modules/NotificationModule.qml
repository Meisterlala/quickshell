import "../components"
import ".."
import QtQuick

ScriptModule {
    moduleName: "notification"
    command: "command -v swaync-client >/dev/null && swaync-client -swb || true"
    interval: 5000
    parseJson: true
    hideEmptyText: false
    backgroundVisible: false
    fontPixelSize: theme.notificationFontPixelSize
    horizontalPadding: 4
    minimumWidth: 26
    format: "{icon}"
    formatIcons: ({
        "notification": "󱅫",
        "none": "󰂜",
        "dnd-notification": "󰂠",
        "dnd-none": "󰪓",
        "inhibited-notification": "󰂛",
        "inhibited-none": "󰪑",
        "dnd-inhibited-notification": "󰂛",
        "dnd-inhibited-none": "󰪑"
    })
    onClickCommand: "swaync-client -t -sw"
    onRightClickCommand: "swaync-client -d -sw"

    Theme {
        id: theme
    }
}
