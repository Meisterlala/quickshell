import "../components"
import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

ClippingRectangle {
    id: root

    required property var barWindow
    property var ipc: null
    property bool moduleVisible: true
    property int interval: 10000
    property string moduleName: "fritz-traffic"
    property string command: "/home/misti/.config/quickshell/main/scripts/fritz_traffic.py"
    property bool dataVisible: false
    property real downMbit: 0
    property real upMbit: 0
    property real downLimitMbit: 250
    property real upLimitMbit: 50
    property real downRatio: 0
    property real upRatio: 0
    property real maxRatio: 0
    property real warnAt: 0.75
    property real criticalAt: 0.9
    property real hideAt: 0.65
    property string state: "normal"
    property string errorText: ""
    readonly property string accent: errorText.length > 0 || state === "critical" ? theme.red : state === "warning" ? theme.yellow : theme.sky
    readonly property string accentSoft: theme.alpha(String(accent), state === "critical" ? 0.42 : 0.3)
    readonly property bool tooltipVisible: mouse.containsMouse && visible

    function clampPercent(value) {
        return Math.max(0, Math.min(100, Number(value || 0)));
    }

    function percentText(ratio) {
        return `${Math.round(clampPercent(ratio * 100))}%`;
    }

    function rateText(mbit) {
        const value = Number(mbit || 0);
        if (value >= 100)
            return `${value.toFixed(0)}M`;
        if (value >= 10)
            return `${value.toFixed(1)}M`;
        return `${value.toFixed(2)}M`;
    }

    function compactText() {
        if (errorText.length > 0)
            return "err";

        const parts = [];
        if (downRatio >= warnAt)
            parts.push(`↓${rateText(downMbit)}`);
        if (upRatio >= warnAt)
            parts.push(`↑${rateText(upMbit)}`);
        return parts.join(" ");
    }

    function refresh() {
        if (!moduleVisible)
            return;

        refreshRunner.exec(["/usr/sbin/python3", command]);
    }

    function openFritzBox() {
        actionRunner.exec(["/usr/sbin/xdg-open", "http://fritz.box"]);
    }

    function applyOutput(output) {
        const trimmed = output.trim();
        if (trimmed.length === 0) {
            errorText = "No FRITZ!Box traffic output";
            dataVisible = true;
            state = "error";
            return;
        }

        try {
            const lines = trimmed.split("\n").filter(line => line.trim().length > 0);
            const parsed = JSON.parse(lines[lines.length - 1]);
            dataVisible = Boolean(parsed.visible);
            state = String(parsed.state || "normal");
            errorText = String(parsed.error || "");
            downMbit = Number(parsed.downMbit || 0);
            upMbit = Number(parsed.upMbit || 0);
            downLimitMbit = Number(parsed.downLimitMbit || downLimitMbit);
            upLimitMbit = Number(parsed.upLimitMbit || upLimitMbit);
            downRatio = Number(parsed.downRatio || 0);
            upRatio = Number(parsed.upRatio || 0);
            maxRatio = Number(parsed.maxRatio || 0);
            warnAt = Number(parsed.warnAt || warnAt);
            criticalAt = Number(parsed.criticalAt || criticalAt);
            hideAt = Number(parsed.hideAt || hideAt);
        } catch (error) {
            errorText = trimmed;
            dataVisible = true;
            state = "error";
        }
    }

    implicitWidth: compactContent.implicitWidth + 20
    implicitHeight: 34
    radius: 8
    color: mouse.containsMouse ? theme.surface2 : theme.alpha(theme.surface0, 0.28)
    border.color: errorText.length > 0 ? theme.alpha(theme.red, 0.72) : theme.alpha(theme.text, 0.1)
    border.width: 1
    contentUnderBorder: true
    visible: moduleVisible && dataVisible

    Theme {
        id: theme
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: root.errorText.length === 0
        width: parent.width * root.clampPercent(root.maxRatio * 100) / 100
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
            text: root.errorText.length > 0 ? "󰤭" : "󰤨"
            textFormat: Text.PlainText
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: root.errorText.length > 0 ? theme.red : theme.text
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: root.compactText()
            textFormat: Text.PlainText
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                root.openFritzBox();
            else
                root.refresh();
        }
    }

    PopupWindow {
        id: tooltipWindow

        readonly property int margin: 8

        anchor.window: root.barWindow
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeY
        anchor.rect.x: root.barWindow ? Math.max(margin, Math.min(root.barWindow.width - width - margin, root.mapToItem(null, 0, 0).x + root.width / 2 - width / 2)) : 0
        anchor.rect.y: root.barWindow ? root.barWindow.height + margin : root.height + margin
        anchor.rect.width: root.width
        anchor.rect.height: root.height
        implicitWidth: 360
        implicitHeight: detailsColumn.implicitHeight + 28
        color: "transparent"
        visible: root.barWindow && root.tooltipVisible

        PopupSurface {
            anchors.fill: parent
            clip: true

            Column {
                id: detailsColumn

                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.accent
                        font.family: theme.fontFamily
                        font.pixelSize: theme.barFontPixelSize + 4
                        text: root.errorText.length > 0 ? "󰤭" : "󰤨"
                    }

                    Column {
                        width: parent.width - 32
                        spacing: 2

                        Text {
                            width: parent.width
                            color: theme.text
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize + 2
                            font.bold: true
                            text: "FRITZ!Box traffic"
                        }

                        Text {
                            width: parent.width
                            visible: root.errorText.length > 0
                            color: root.errorText.length > 0 ? theme.red : theme.subtext0
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize
                            text: root.errorText
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                        }
                    }
                }

                TrafficBar {
                    width: parent.width
                    visible: root.errorText.length === 0
                    label: "Down"
                    icon: "↓"
                    rate: root.downMbit
                    limit: root.downLimitMbit
                    percent: root.downRatio * 100
                    accent: root.downRatio >= root.criticalAt ? theme.red : root.downRatio >= root.warnAt ? theme.yellow : theme.sky
                }

                TrafficBar {
                    width: parent.width
                    visible: root.errorText.length === 0
                    label: "Up"
                    icon: "↑"
                    rate: root.upMbit
                    limit: root.upLimitMbit
                    percent: root.upRatio * 100
                    accent: root.upRatio >= root.criticalAt ? theme.red : root.upRatio >= root.warnAt ? theme.yellow : theme.green
                }
            }
        }
    }

    component TrafficBar: Item {
        id: barRoot

        required property string label
        required property string icon
        required property real rate
        required property real limit
        required property real percent
        required property string accent

        height: 28

        ClippingRectangle {
            anchors.fill: parent
            radius: 6
            color: theme.alpha(theme.crust, 0.3)
            border.color: theme.alpha(String(barRoot.accent), 0.22)
            border.width: 1
            contentUnderBorder: true

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                visible: barRoot.percent > 0
                width: parent.width * root.clampPercent(barRoot.percent) / 100
                color: theme.alpha(String(barRoot.accent), 0.36)
            }
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 66
                color: barRoot.accent
                font.family: theme.fontFamily
                font.pixelSize: theme.tooltipFontPixelSize
                text: `${barRoot.icon} ${barRoot.label}`
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 74
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: theme.tooltipFontPixelSize
                horizontalAlignment: Text.AlignRight
                text: `${root.rateText(barRoot.rate)} / ${Math.round(barRoot.limit)}M (${Math.round(root.clampPercent(barRoot.percent))}%)`
            }
        }
    }

    Component.onCompleted: refresh()
    onModuleVisibleChanged: {
        if (moduleVisible)
            refresh();
        else
            dataVisible = false;
    }

    Timer {
        interval: root.interval
        running: root.moduleVisible && !root.tooltipVisible && root.interval > 0
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 1000
        running: root.moduleVisible && root.tooltipVisible
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

    Connections {
        function onRefreshRequested(name) {
            if (name === root.moduleName || name === "all")
                root.refresh();
        }

        target: root.ipc
    }
}
