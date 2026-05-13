import "../components"
import QtQuick

ScriptModule {
    moduleName: "notification"
    command: "command -v swaync-client >/dev/null && swaync-client -swb || true"
    interval: 5000
    parseJson: true
    onClickCommand: "swaync-client -t -sw"
    onRightClickCommand: "swaync-client -d -sw"
}
