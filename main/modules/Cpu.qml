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
    property int interval: 3000
    property int hoverInterval: 1000
    property var previousStats: ({})
    property real currentUsage: 0
    property var cores: []
    property var usageHistory: []
    property int historySampleCounter: 0
    property string load1: "0.00"
    property string load5: "0.00"
    property string load15: "0.00"
    readonly property string statCommand: "awk '/^cpu[0-9 ]/ {print}' /proc/stat"
    readonly property string loadCommand: "awk '{print $1, $2, $3}' /proc/loadavg"
    readonly property bool tooltipVisible: mouse.containsMouse && cores.length > 0

    function clampPercent(value) {
        return Math.max(0, Math.min(100, Number(value || 0)));
    }

    function usageClass(value) {
        if (value > 95)
            return "critical";

        if (value > 90)
            return "warning";

        return "";
    }

    function usageBarColor(value) {
        const usageState = usageClass(value);
        if (usageState.length > 0)
            return theme.alpha(theme.classColor(usageState), 0.48);

        return theme.alpha(theme.text, 0.32);
    }

    function loadColor(value) {
        const coreCount = Math.max(1, cores.length);
        const normalized = Number(value || 0) / coreCount;

        if (normalized > 1)
            return theme.red;

        if (normalized > 0.7)
            return theme.yellow;

        return theme.green;
    }

    function loadText(value) {
        return Number(value || 0).toFixed(2).padStart(5, " ");
    }

    function coreLabel(name) {
        return `Core ${String(name).slice(3)}`;
    }

    function coreNames(stats) {
        return Object.keys(stats).filter(name => name.match(/^cpu\d+$/)).sort((left, right) => Number(left.slice(3)) - Number(right.slice(3)));
    }

    function shouldAppendHistory() {
        if (!mouse.containsMouse)
            return true;

        historySampleCounter += 1;
        if (historySampleCounter < Math.max(1, Math.round(interval / hoverInterval)))
            return false;

        historySampleCounter = 0;
        return true;
    }

    function appendUsageHistory(value) {
        const nextHistory = usageHistory.slice();
        nextHistory.push(clampPercent(value));
        usageHistory = nextHistory.slice(Math.max(0, nextHistory.length - 48));
    }

    function resetSamples() {
        previousStats = ({});
        historySampleCounter = 0;
    }

    function statTotals(values) {
        const idle = Number(values[3] || 0) + Number(values[4] || 0);
        let total = 0;
        for (const value of values)
            total += Number(value || 0);

        return {
            "idle": idle,
            "total": total
        };
    }

    function parseStats(output) {
        const stats = {};
        const lines = output.trim().split("\n");

        for (const line of lines) {
            const parts = line.trim().split(/\s+/);
            if (parts.length < 5 || !parts[0].match(/^cpu/))
                continue;

            stats[parts[0]] = parts.slice(1).map(value => Number(value));
        }

        return stats;
    }

    function usageFor(name, stats) {
        const previous = previousStats[name];
        const current = stats[name];
        if (!previous || !current)
            return 0;

        const previousTotals = statTotals(previous);
        const currentTotals = statTotals(current);
        const totalDelta = currentTotals.total - previousTotals.total;
        const idleDelta = currentTotals.idle - previousTotals.idle;
        if (totalDelta <= 0)
            return 0;

        return clampPercent((totalDelta - idleDelta) * 100 / totalDelta);
    }

    function applyOutput(output) {
        const stats = parseStats(output);
        const hasPrevious = Object.keys(previousStats).length > 0;

        if (hasPrevious) {
            currentUsage = usageFor("cpu", stats);
            if (shouldAppendHistory())
                appendUsageHistory(currentUsage);

            cores = coreNames(stats).map(name => ({
                "name": name,
                "usage": usageFor(name, stats)
            }));
        }

        previousStats = stats;
    }

    function applyLoadOutput(output) {
        const parts = output.trim().split(/\s+/);
        if (parts.length < 3)
            return;

        load1 = parts[0];
        load5 = parts[1];
        load15 = parts[2];
    }

    function refresh() {
        if (!moduleVisible)
            return;

        refreshRunner.exec(["/usr/bin/sh", "-lc", statCommand]);
        loadRunner.exec(["/usr/bin/sh", "-lc", loadCommand]);
    }

    implicitWidth: compactContent.implicitWidth + 20
    implicitHeight: 34
    radius: 8
    color: mouse.containsMouse ? theme.surface2 : theme.alpha(theme.surface0, 0.28)
    border.color: theme.alpha(theme.text, 0.1)
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
            color: theme.classColor(root.usageClass(root.currentUsage))
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(root.currentUsage).toString().padStart(2, " ")}%`
            textFormat: Text.PlainText
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: theme.classColor(root.usageClass(root.currentUsage))
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: ""
            textFormat: Text.PlainText
        }
    }

    PopupWindow {
        id: tooltipWindow

        readonly property int margin: 8
        readonly property int maxTooltipHeight: root.barWindow && root.barWindow.screen ? Math.max(120, Math.round((root.barWindow.screen.height - root.barWindow.height - margin * 2) * 0.75)) : 480

        anchor.window: root.barWindow
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeY
        anchor.rect.x: root.barWindow ? Math.max(margin, Math.min(root.barWindow.width - width - margin, root.mapToItem(null, 0, 0).x + root.width / 2 - width / 2)) : 0
        anchor.rect.y: root.barWindow ? root.barWindow.height + margin : root.height + margin
        anchor.rect.width: root.width
        anchor.rect.height: root.height
        implicitWidth: 430
        implicitHeight: Math.min(maxTooltipHeight, detailsColumn.implicitHeight + 28)
        color: "transparent"
        visible: root.barWindow && root.tooltipVisible

        PopupSurface {
            anchors.fill: parent
            clip: true

            Flickable {
                anchors.fill: parent
                anchors.margins: 14
                contentWidth: width
                contentHeight: detailsColumn.implicitHeight
                clip: true

                Column {
                    id: detailsColumn

                    width: parent.width
                    spacing: 6

                    LoadHeader {
                        width: parent.width
                        text: "Load"
                    }

                    UsageHistogram {
                        width: parent.width
                        height: 92
                        values: root.usageHistory
                        maxSamples: 48
                        warningThreshold: 90
                        criticalThreshold: 95
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: theme.alpha(theme.text, 0.1)
                    }

                    TooltipHeader {
                        width: parent.width
                        text: "CPU Usage per Core"
                    }

                    Grid {
                        id: coreGrid

                        width: parent.width
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 6

                        Repeater {
                            model: root.cores

                            CpuCoreBar {
                                required property var modelData

                                width: (coreGrid.width - coreGrid.columnSpacing) / coreGrid.columns
                                name: root.coreLabel(modelData.name)
                                usage: modelData.usage
                            }
                        }
                    }
                }
            }
        }
    }

    component CpuCoreBar: Item {
        id: barRoot

        required property string name
        required property real usage

        height: 18

        ClippingRectangle {
            anchors.fill: parent
            radius: 4
            color: theme.alpha(theme.crust, 0.3)
            border.color: theme.alpha(theme.text, 0.1)
            border.width: 1
            contentUnderBorder: true

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(2, parent.width * barRoot.usage / 100)
                color: root.usageBarColor(barRoot.usage)
            }
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: 11
                text: barRoot.name
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 48
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: 11
                horizontalAlignment: Text.AlignRight
                text: `${Math.round(barRoot.usage)}%`
            }
        }
    }

    component TooltipHeader: Text {
        color: theme.text
        font.family: theme.fontFamily
        font.pixelSize: theme.tooltipFontPixelSize + 1
        font.bold: true
    }

    component LoadHeader: Item {
        required property string text

        height: title.implicitHeight

        TooltipHeader {
            id: title

            anchors.left: parent.left
            text: parent.text
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            LoadMetric {
                label: "1min"
                value: root.load1
            }

            LoadMetric {
                label: "5min"
                value: root.load5
            }

            LoadMetric {
                label: "15min"
                value: root.load15
            }
        }
    }

    component LoadMetric: Row {
        required property string label
        required property string value

        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: theme.subtext0
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize
            text: parent.label
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            color: root.loadColor(parent.value)
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize
            horizontalAlignment: Text.AlignRight
            text: root.loadText(parent.value)
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
            root.historySampleCounter = 0;
            if (containsMouse)
                root.refresh();

        }
    }

    Timer {
        id: refreshTimer

        interval: mouse.containsMouse ? root.hoverInterval : root.interval
        running: root.moduleVisible && interval > 0
        repeat: true
        onTriggered: root.refresh()
        onIntervalChanged: {
            if (running)
                restart();

        }
    }

    Process {
        id: refreshRunner

        stdout: StdioCollector {
            onStreamFinished: root.applyOutput(this.text)
        }
    }

    Process {
        id: loadRunner

        stdout: StdioCollector {
            onStreamFinished: root.applyLoadOutput(this.text)
        }
    }

    Component.onCompleted: refresh()
    onModuleVisibleChanged: {
        resetSamples();
        if (moduleVisible)
            refresh();

    }
}
