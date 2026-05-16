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
    property int interval: 5000
    property real memTotal: 0
    property real memAvailable: 0
    property real memFree: 0
    property real buffers: 0
    property real cached: 0
    property real swapTotal: 0
    property real swapFree: 0
    property string errorText: ""
    readonly property string memCommand: "awk '/^(MemTotal|MemAvailable|MemFree|Buffers|Cached|SwapTotal|SwapFree):/ {print $1, $2}' /proc/meminfo"
    readonly property real memUsed: Math.max(0, memTotal - memAvailable)
    readonly property real swapUsed: Math.max(0, swapTotal - swapFree)
    readonly property real memPercent: memTotal > 0 ? clampPercent(memUsed * 100 / memTotal) : 0
    readonly property real swapPercent: swapTotal > 0 ? clampPercent(swapUsed * 100 / swapTotal) : 0
    readonly property string state: errorText.length > 0 ? "error" : memPercent >= 95 ? "critical" : memPercent >= 85 ? "warning" : "normal"
    readonly property string accent: state === "error" || state === "critical" ? theme.red : state === "warning" ? theme.yellow : theme.sky
    readonly property bool tooltipVisible: mouse.containsMouse

    function clampPercent(value) {
        return Math.max(0, Math.min(100, Number(value || 0)));
    }

    function gibText(valueKiB) {
        return `${(Number(valueKiB || 0) / 1048576).toFixed(1)} GiB`;
    }

    function applyMetric(name, value) {
        const number = Number(value || 0);
        if (name === "MemTotal")
            memTotal = number;
        else if (name === "MemAvailable")
            memAvailable = number;
        else if (name === "MemFree")
            memFree = number;
        else if (name === "Buffers")
            buffers = number;
        else if (name === "Cached")
            cached = number;
        else if (name === "SwapTotal")
            swapTotal = number;
        else if (name === "SwapFree")
            swapFree = number;
    }

    function refresh() {
        if (!moduleVisible)
            return;

        refreshRunner.exec(["/usr/bin/sh", "-lc", memCommand]);
    }

    function applyOutput(output) {
        const trimmed = output.trim();
        if (trimmed.length === 0) {
            errorText = "No memory output";
            return;
        }

        for (const line of trimmed.split("\n")) {
            const parts = line.trim().replace(":", "").split(/\s+/);
            if (parts.length >= 2)
                applyMetric(parts[0], parts[1]);
        }

        if (memTotal <= 0)
            errorText = "Unable to read memory totals";
        else
            errorText = "";
    }

    implicitWidth: compactContent.implicitWidth + 20
    implicitHeight: 34
    radius: 8
    color: mouse.containsMouse ? theme.surface2 : theme.alpha(theme.surface0, 0.28)
    border.color: errorText.length > 0 ? theme.alpha(theme.red, 0.72) : theme.alpha(theme.text, 0.1)
    border.width: 1
    contentUnderBorder: true
    visible: moduleVisible

    Theme {
        id: theme
    }

    Row {
        id: compactContent

        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            color: root.accent
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            horizontalAlignment: Text.AlignRight
            text: root.errorText.length > 0 ? "err" : `${Math.round(root.memPercent).toString().padStart(2, " ")}%`
            textFormat: Text.PlainText
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: root.accent
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: root.errorText.length > 0 ? "" : ""
            textFormat: Text.PlainText
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
        implicitWidth: 340
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
                        font.pixelSize: theme.barFontPixelSize + 3
                        text: root.errorText.length > 0 ? "" : ""
                    }

                    Column {
                        width: parent.width - 30
                        spacing: 2

                        Text {
                            width: parent.width
                            color: theme.text
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize + 1
                            font.bold: true
                            text: "Memory"
                        }

                        Text {
                            width: parent.width
                            color: root.errorText.length > 0 ? theme.red : theme.subtext0
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize
                            text: root.errorText.length > 0 ? root.errorText : `${root.gibText(root.memUsed)} used of ${root.gibText(root.memTotal)}`
                        }
                    }
                }

                MetricBar {
                    width: parent.width
                    visible: root.errorText.length === 0
                    label: "RAM"
                    percent: root.memPercent
                    valueText: `${root.gibText(root.memUsed)} / ${root.gibText(root.memTotal)}`
                    accent: root.accent
                    fillColor: theme.alpha(String(root.accent), 0.36)
                }

                MetricBar {
                    width: parent.width
                    visible: root.errorText.length === 0 && root.swapTotal > 0
                    label: "Swap"
                    percent: root.swapPercent
                    valueText: `${root.gibText(root.swapUsed)} / ${root.gibText(root.swapTotal)}`
                    accent: root.swapPercent >= 80 ? theme.yellow : theme.sky
                    fillColor: theme.alpha(root.swapPercent >= 80 ? theme.yellow : theme.sky, 0.32)
                }

                Rectangle {
                    visible: root.errorText.length === 0
                    width: parent.width
                    height: 1
                    color: theme.alpha(theme.text, 0.1)
                }

                Grid {
                    visible: root.errorText.length === 0
                    width: parent.width
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 4

                    DetailMetric {
                        width: (parent.width - parent.columnSpacing) / parent.columns
                        label: "Available"
                        value: root.gibText(root.memAvailable)
                    }

                    DetailMetric {
                        width: (parent.width - parent.columnSpacing) / parent.columns
                        label: "Free"
                        value: root.gibText(root.memFree)
                    }

                    DetailMetric {
                        width: (parent.width - parent.columnSpacing) / parent.columns
                        label: "Cache"
                        value: root.gibText(root.cached)
                    }

                    DetailMetric {
                        width: (parent.width - parent.columnSpacing) / parent.columns
                        label: "Buffers"
                        value: root.gibText(root.buffers)
                    }
                }
            }
        }
    }

    component MetricBar: Item {
        id: metricRoot

        required property string label
        required property real percent
        required property string valueText
        required property string accent
        required property string fillColor

        height: 24

        ClippingRectangle {
            anchors.fill: parent
            radius: 5
            color: theme.alpha(theme.crust, 0.3)
            border.color: theme.alpha(String(metricRoot.accent), 0.22)
            border.width: 1
            contentUnderBorder: true

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                visible: metricRoot.percent > 0
                width: parent.width * root.clampPercent(metricRoot.percent) / 100
                color: metricRoot.fillColor
            }
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 7
            anchors.rightMargin: 7

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: 11
                text: metricRoot.label
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 52
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: 11
                horizontalAlignment: Text.AlignRight
                text: metricRoot.valueText
            }
        }
    }

    component DetailMetric: Row {
        required property string label
        required property string value

        height: 18
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 62
            color: theme.subtext0
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize
            text: parent.label
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 68
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize
            horizontalAlignment: Text.AlignRight
            text: parent.value
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        z: 10
        onClicked: root.refresh()
        onContainsMouseChanged: {
            if (containsMouse)
                root.refresh();

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

    Component.onCompleted: refresh()
    onModuleVisibleChanged: {
        if (moduleVisible)
            refresh();
        else
            errorText = "";

    }
}
