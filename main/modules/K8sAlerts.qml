import "../components"
import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

ClippingRectangle {
    id: root

    required property var barWindow
    property bool moduleVisible: true
    property int interval: 60000
    property string command: "/home/misti/.config/quickshell/main/scripts/k8s_alerts.py"
    property string contextName: ""
    property string alertNamespace: ""
    property bool watchdogRunning: false
    property var counts: ({"total": 0, "critical": 0, "error": 0, "warning": 0, "info": 0, "unknown": 0})
    property var alerts: []
    property string state: "ok"
    property string errorText: ""
    property bool popupPinned: false
    property real lastInteractiveRefresh: 0
    readonly property int interactiveRefreshCooldown: 5000
    readonly property bool hasProblem: state !== "ok" || errorText.length > 0 || !watchdogRunning
    readonly property bool tooltipVisible: (mouse.containsMouse || popupPinned) && visible
    readonly property string accent: state === "critical" || state === "error" || errorText.length > 0 ? theme.red : state === "warning" ? theme.yellow : theme.green
    readonly property string accentSoft: theme.alpha(String(accent), state === "critical" ? 0.42 : 0.32)

    function plainTooltip(value) {
        return String(value ?? "").replace(/\r/g, "\n").replace(/<[^>]*>/g, "").trim();
    }

    function refresh() {
        if (!moduleVisible)
            return;

        refreshRunner.exec(["/usr/sbin/python3", command]);
    }

    function refreshInteractive() {
        const now = Date.now();
        if (now - lastInteractiveRefresh < interactiveRefreshCooldown)
            return;

        lastInteractiveRefresh = now;
        refresh();
    }

    function runCommand(commandText) {
        actionRunner.exec(["/usr/sbin/sh", "-lc", commandText]);
    }

    function severityColor(severity) {
        const sev = String(severity || "").toLowerCase();
        if (sev === "critical" || sev === "error")
            return theme.red;
        if (sev === "warning")
            return theme.yellow;
        if (sev === "info")
            return theme.sky;
        return theme.subtext0;
    }

    function severityLabel(severity) {
        const sev = String(severity || "unknown");
        return sev.charAt(0).toUpperCase() + sev.slice(1);
    }

    function applyOutput(output) {
        const trimmed = output.trim();
        if (trimmed.length === 0) {
            errorText = "No Alertmanager output";
            state = "error";
            return;
        }

        try {
            const lines = trimmed.split("\n").filter(line => line.trim().length > 0);
            const parsed = JSON.parse(lines[lines.length - 1]);
            state = String(parsed.state || parsed.class || "ok");
            errorText = plainTooltip(parsed.error || "");
            contextName = String(parsed.context || "");
            alertNamespace = String(parsed.namespace || "");
            watchdogRunning = Boolean(parsed.watchdogRunning);
            counts = parsed.counts || counts;
            alerts = parsed.alerts || [];
            if (state === "ok")
                popupPinned = false;
        } catch (error) {
            errorText = plainTooltip(trimmed);
            state = "error";
        }
    }

    implicitWidth: compactContent.implicitWidth + 20
    implicitHeight: 34
    radius: 8
    color: mouse.containsMouse ? theme.surface2 : theme.alpha(theme.surface0, 0.28)
    border.color: theme.alpha(theme.text, 0.1)
    border.width: 1
    contentUnderBorder: true
    visible: moduleVisible && hasProblem

    Theme {
        id: theme
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width
        radius: 0
        color: root.accentSoft
    }

    Row {
        id: compactContent

        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: root.accent
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: root.state === "critical" || root.state === "error" || root.errorText.length > 0 ? "" : ""
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: Number(root.counts.total || 0) > 0 ? String(root.counts.total) : "AM"
        }

    }

    PopupWindow {
        id: tooltipWindow

        readonly property int margin: 8
        readonly property int maxPopupHeight: root.barWindow && root.barWindow.screen ? Math.max(180, Math.round((root.barWindow.screen.height - root.barWindow.height - margin * 2) * 0.78)) : 560

        anchor.window: root.barWindow
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeY
        anchor.rect.x: root.barWindow ? Math.max(margin, Math.min(root.barWindow.width - width - margin, root.mapToItem(null, 0, 0).x + root.width / 2 - width / 2)) : 0
        anchor.rect.y: root.barWindow ? root.barWindow.height + margin : root.height + margin
        anchor.rect.width: root.width
        anchor.rect.height: root.height
        implicitWidth: 440
        implicitHeight: Math.min(maxPopupHeight, popupContent.implicitHeight + 28)
        color: "transparent"
        visible: root.barWindow && root.tooltipVisible

        PopupSurface {
            anchors.fill: parent
            clip: true

            Column {
                id: popupContent

                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        color: root.accent
                        font.family: theme.fontFamily
                        font.pixelSize: theme.barFontPixelSize + 4
                        text: root.state === "critical" || root.state === "error" || root.errorText.length > 0 ? "" : ""
                    }

                    Column {
                        width: parent.width - 30
                        spacing: 2

                        Text {
                            width: parent.width
                            color: theme.text
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize + 2
                            font.bold: true
                            text: "Kubernetes alerts"
                        }

                        Text {
                            width: parent.width
                            color: theme.subtext0
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize
                            elide: Text.ElideRight
                            text: `${root.contextName || "no context"} · ${root.alertNamespace || "no alertmanager namespace"}`
                        }
                    }
                }

                Text {
                    visible: root.errorText.length > 0
                    width: parent.width
                    color: theme.red
                    font.family: theme.fontFamily
                    font.pixelSize: theme.tooltipFontPixelSize
                    wrapMode: Text.Wrap
                    text: root.errorText
                }

                Text {
                    visible: root.errorText.length === 0 && !root.watchdogRunning
                    width: parent.width
                    color: theme.red
                    font.family: theme.fontFamily
                    font.pixelSize: theme.tooltipFontPixelSize
                    font.bold: true
                    wrapMode: Text.Wrap
                    text: "Watchdog alert is missing. Alertmanager may not be reporting correctly."
                }

                Row {
                    visible: root.errorText.length === 0
                    width: parent.width
                    spacing: 6

                    SummaryChip {
                        label: "crit"
                        value: Number(root.counts.critical || 0)
                        colorValue: theme.red
                    }

                    SummaryChip {
                        label: "error"
                        value: Number(root.counts.error || 0)
                        colorValue: theme.red
                    }

                    SummaryChip {
                        label: "warn"
                        value: Number(root.counts.warning || 0)
                        colorValue: theme.yellow
                    }

                    SummaryChip {
                        label: "info"
                        value: Number(root.counts.info || 0)
                        colorValue: theme.sky
                    }

                    SummaryChip {
                        label: "other"
                        value: Number(root.counts.unknown || 0)
                        colorValue: theme.subtext0
                        visible: value > 0
                    }
                }

                Flickable {
                    visible: root.errorText.length === 0
                    width: parent.width
                    height: Math.min(320, alertsColumn.implicitHeight)
                    contentWidth: width
                    contentHeight: alertsColumn.implicitHeight
                    clip: true

                    Column {
                        id: alertsColumn

                        width: parent.width
                        spacing: 8

                        Text {
                            visible: root.alerts.length === 0
                            width: parent.width
                            color: theme.subtext0
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize
                            text: "No active alerts."
                        }

                        Repeater {
                            model: root.alerts

                            AlertCard {
                                required property var modelData

                                width: alertsColumn.width
                                alert: modelData || ({})
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: theme.alpha(theme.text, 0.1)
                }

                Row {
                    width: parent.width
                    spacing: 8

                    ActionButton {
                        label: "Refresh"
                        colorValue: root.accent
                        onPressed: root.refresh()
                    }

                    ActionButton {
                        label: "Open k9s"
                        colorValue: theme.sky
                        onPressed: root.runCommand("ghostty -e k9s")
                    }

                    ActionButton {
                        label: "Alerts"
                        colorValue: theme.yellow
                        onPressed: root.runCommand("ghostty -e bash -lc 'kubectl get alerts -A || kubectl get prometheusrules -A; echo; read -rp \"Press Enter to close...\"'")
                    }
                }
            }
        }
    }

    component SummaryChip: Rectangle {
        id: chip

        required property string label
        required property int value
        required property string colorValue

        implicitWidth: chipText.implicitWidth + 14
        implicitHeight: 24
        radius: 7
        color: theme.alpha(String(colorValue), 0.16)
        border.color: theme.alpha(String(colorValue), 0.32)
        border.width: 1

        Text {
            id: chipText

            anchors.centerIn: parent
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: 11
            text: `${chip.label} ${chip.value}`
        }
    }

    component AlertCard: Rectangle {
        id: card

        required property var alert
        readonly property string sevColor: root.severityColor(alert.severity)
        readonly property string messageText: String(alert.message || alert.summary || alert.description || "")

        width: parent ? parent.width : 0
        implicitHeight: cardColumn.implicitHeight + 16
        radius: 10
        color: theme.alpha(theme.crust, 0.25)
        border.color: theme.alpha(sevColor, 0.28)
        border.width: 1

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 4
            radius: 2
            color: card.sevColor
        }

        Column {
            id: cardColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            anchors.leftMargin: 12
            spacing: 4

            Row {
                width: parent.width
                spacing: 7

                Text {
                    color: card.sevColor
                    font.family: theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    text: root.severityLabel(card.alert.severity)
                }

                Text {
                    width: parent.width - 70
                    color: theme.text
                    font.family: theme.fontFamily
                    font.pixelSize: theme.tooltipFontPixelSize
                    font.bold: true
                    elide: Text.ElideRight
                    text: String(card.alert.name || "unknown")
                }
            }

            Text {
                width: parent.width
                color: theme.subtext0
                font.family: theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
                text: `${card.alert.namespace || "-"}${card.alert.startsAt ? " · since " + card.alert.startsAt : ""}`
            }

            Text {
                visible: card.messageText.length > 0
                width: parent.width
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: theme.tooltipFontPixelSize
                wrapMode: Text.Wrap
                text: card.messageText
            }
        }
    }

    component ActionButton: Rectangle {
        id: button

        required property string label
        required property string colorValue
        signal pressed()

        implicitWidth: buttonText.implicitWidth + 18
        implicitHeight: 26
        radius: 7
        color: buttonMouse.containsMouse ? theme.alpha(String(colorValue), 0.35) : theme.alpha(String(colorValue), 0.18)
        border.color: theme.alpha(String(colorValue), 0.38)
        border.width: 1

        Text {
            id: buttonText

            anchors.centerIn: parent
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: 11
            text: button.label
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            hoverEnabled: true
            onClicked: button.pressed()
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        z: 10
        onContainsMouseChanged: {
            if (containsMouse)
                root.refreshInteractive();
        }
        onClicked: (event) => {
            if (event.button === Qt.LeftButton) {
                root.popupPinned = !root.popupPinned;
                if (root.popupPinned)
                    root.refreshInteractive();
            } else if (event.button === Qt.RightButton) {
                root.refresh();
            }
        }
    }

    Timer {
        interval: root.interval
        running: root.moduleVisible && root.interval > 0
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: refreshRunner

        stdout: StdioCollector {
            onStreamFinished: root.applyOutput(this.text)
        }
    }

    Process {
        id: actionRunner
    }

    Component.onCompleted: refresh()
    onModuleVisibleChanged: {
        if (moduleVisible)
            refresh();
        else
            popupPinned = false;
    }
}
