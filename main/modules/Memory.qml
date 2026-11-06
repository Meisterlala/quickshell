pragma ComponentBehavior: Bound

import "../components"
import ".."
import "../components/ModuleData.js" as ModuleData
import QtQuick
import Quickshell.Io
import Quickshell.Widgets

ClippingRectangle {
    id: root

    required property var barWindow
    property var ipc: null
    property bool moduleVisible: true
    property int interval: 5000
    property real memTotal: 0
    property real memAvailable: 0
    property real memFree: 0
    property real buffers: 0
    property real cached: 0
    property real shmem: 0
    property real anonPages: 0
    property bool kernelAvailable: false
    property real sReclaimable: 0
    property real kReclaimable: -1
    property real zswap: 0
    property real zswapped: 0
    property real swapTotal: 0
    property real swapFree: 0
    property real tmpfsUsed: 0
    property bool tmpfsAvailable: false
    property string errorText: ""
    readonly property string memCommand: ["awk '/^(MemTotal|MemAvailable|MemFree|Buffers|Cached|Shmem|AnonPages|SReclaimable|KReclaimable|Zswap|Zswapped|SwapTotal|SwapFree):/ {print $1, $2}' /proc/meminfo", "LC_ALL=C df -k --output=used -t tmpfs | awk 'NR > 1 {used += $1; count++} END {if (count > 0) print \"TmpfsUsed\", used}'"].join("; ")
    // Exclude reclaimable file/kernel caches, but keep tmpfs and compressed RAM.
    // KReclaimable already contains SReclaimable; never subtract both.
    readonly property real reclaimableCache: Math.max(0, cached - shmem) + buffers + Math.max(0, kReclaimable >= 0 ? kReclaimable : sReclaimable)
    readonly property real memUsed: Math.max(0, Math.min(memTotal, memTotal - memFree - reclaimableCache))
    // Kernel/driver estimate: the residual after resident anonymous/shared
    // application pages and zswap. Also includes unclassified allocations.
    readonly property real kernelUsed: kernelAvailable ? Math.max(0, memUsed - anonPages - shmem - zswap) : 0
    readonly property real swapUsed: Math.max(0, swapTotal - swapFree)
    readonly property string kernelAccent: "#fab387"
    readonly property string zswapAccent: "#cba6f7"
    readonly property real memPercent: memTotal > 0 ? ModuleData.clampPercent(memUsed * 100 / memTotal) : 0
    readonly property real kernelPercent: memTotal > 0 ? ModuleData.clampPercent(kernelUsed * 100 / memTotal) : 0
    readonly property real zswapPercent: memTotal > 0 ? ModuleData.clampPercent(zswap * 100 / memTotal) : 0
    readonly property real swapPercent: swapTotal > 0 ? ModuleData.clampPercent(swapUsed * 100 / swapTotal) : 0
    readonly property string state: errorText.length > 0 ? "error" : memPercent >= 95 ? "critical" : memPercent >= 85 ? "warning" : "normal"
    readonly property string accent: state === "error" || state === "critical" ? theme.red : state === "warning" ? theme.yellow : theme.sky
    readonly property bool tooltipVisible: mouse.containsMouse

    function gibText(valueKiB) {
        return `${(Number(valueKiB || 0) / 1048576).toFixed(1)} GiB`;
    }

    function filesystemText(valueKiB) {
        if (valueKiB >= 1048576)
            return gibText(valueKiB);
        return `${(valueKiB / 1024).toFixed(1)} MiB`;
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
        else if (name === "Shmem")
            shmem = number;
        else if (name === "AnonPages")
            anonPages = number;
        else if (name === "SReclaimable")
            sReclaimable = number;
        else if (name === "KReclaimable")
            kReclaimable = number;
        else if (name === "Zswap")
            zswap = number;
        else if (name === "Zswapped")
            zswapped = number;
        else if (name === "SwapTotal")
            swapTotal = number;
        else if (name === "SwapFree")
            swapFree = number;
    }

    function refresh() {
        if (!moduleVisible || refreshRunner.running)
            return;

        refreshRunner.exec(["/usr/bin/sh", "-lc", memCommand]);
    }

    function applyOutput(output) {
        const trimmed = output.trim();
        if (trimmed.length === 0) {
            errorText = "No memory output";
            return;
        }

        const metrics = {};
        for (const line of trimmed.split("\n")) {
            const parts = line.trim().replace(":", "").split(/\s+/);
            const value = Number(parts[1]);
            if (parts.length >= 2 && Number.isFinite(value) && value >= 0)
                metrics[parts[0]] = value;
        }

        if (!(metrics.MemTotal > 0) || metrics.MemFree === undefined || metrics.MemAvailable === undefined) {
            errorText = "Unable to read memory totals";
            return;
        }

        // Reset absent optional counters, e.g. when zswap is unavailable.
        const names = ["MemTotal", "MemAvailable", "MemFree", "Buffers", "Cached", "Shmem", "AnonPages", "SReclaimable", "KReclaimable", "Zswap", "Zswapped", "SwapTotal", "SwapFree"];
        for (const name of names)
            applyMetric(name, metrics[name] !== undefined ? metrics[name] : name === "KReclaimable" ? -1 : 0);
        kernelAvailable = metrics.AnonPages !== undefined;
        tmpfsAvailable = metrics.TmpfsUsed !== undefined;
        tmpfsUsed = tmpfsAvailable ? metrics.TmpfsUsed : 0;
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

    BarPopup {
        id: tooltipWindow

        barWindow: root.barWindow
        anchorItem: root
        shown: root.tooltipVisible
        implicitWidth: 340
        implicitHeight: detailsColumn.implicitHeight + 28

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
                            wrapMode: Text.WordWrap
                            text: root.errorText.length > 0 ? root.errorText : `${root.gibText(root.memUsed)} used of ${root.gibText(root.memTotal)}`
                        }
                    }
                }

                MetricBar {
                    width: parent.width
                    visible: root.errorText.length === 0
                    label: "RAM"
                    percent: root.memPercent
                    leadingPercent: root.kernelPercent
                    leadingFillColor: theme.alpha(root.kernelAccent, 0.55)
                    secondaryPercent: root.zswapPercent
                    secondaryFillColor: theme.alpha(root.zswapAccent, 0.55)
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
                        value: root.gibText(root.reclaimableCache)
                    }

                    DetailMetric {
                        width: (parent.width - parent.columnSpacing) / parent.columns
                        label: "Kernel"
                        textColor: root.kernelAccent
                        value: root.kernelAvailable ? root.gibText(root.kernelUsed) : "—"
                    }

                    DetailMetric {
                        width: (parent.width - parent.columnSpacing) / parent.columns
                        label: "Zswap raw"
                        textColor: root.zswapAccent
                        value: root.gibText(root.zswapped)
                    }

                    DetailMetric {
                        width: (parent.width - parent.columnSpacing) / parent.columns
                        label: "Zswap RAM"
                        textColor: root.zswapAccent
                        value: root.gibText(root.zswap)
                    }

                    DetailMetric {
                        width: (parent.width - parent.columnSpacing) / parent.columns
                        label: "Tmpfs"
                        value: root.tmpfsAvailable ? root.filesystemText(root.tmpfsUsed) : "—"
                    }
                }
            }
        }
    }

    component DetailMetric: Row {
        required property string label
        required property string value
        property string textColor: ""

        height: 18
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 72
            color: parent.textColor.length > 0 ? parent.textColor : theme.subtext0
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize
            text: parent.label
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 78
            color: parent.textColor.length > 0 ? parent.textColor : theme.text
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

    Connections {
        target: root.ipc
        function onRefreshRequested(name) {
            if (name === "memory" || name === "all")
                root.refresh();
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
