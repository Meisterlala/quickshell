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
    property int hoverInterval: 1000
    property real utilization: 0
    property real memoryUsed: 0
    property real memoryTotal: 0
    property string driverVersion: ""
    property string kernelDriverVersion: ""
    property string gpuName: "NVIDIA GPU"
    property string errorText: ""
    readonly property string marker: "__KERNEL_DRIVER__="
    readonly property string queryCommand: "nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,driver_version,name --format=csv,noheader,nounits 2>&1; printf '\\n__KERNEL_DRIVER__='; awk '/NVRM version/ {for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\\.[0-9]+/) {print $i; exit}}' /proc/driver/nvidia/version 2>/dev/null"
    readonly property real memoryPercent: memoryTotal > 0 ? ModuleData.clampPercent(memoryUsed * 100 / memoryTotal) : 0
    readonly property bool driverMismatch: driverVersion.length > 0 && kernelDriverVersion.length > 0 && driverVersion !== kernelDriverVersion
    readonly property bool hasError: errorText.length > 0 || driverMismatch
    readonly property string state: hasError ? "error" : utilization >= 90 ? "warning" : "normal"
    readonly property string accent: hasError ? theme.red : utilization >= 90 ? theme.yellow : theme.sky
    readonly property string accentSoft: theme.alpha(String(accent), hasError ? 0.34 : 0.28)
    readonly property bool tooltipVisible: mouse.containsMouse

    function mibText(value) {
        const number = Number(value || 0);
        if (number >= 1024)
            return `${(number / 1024).toFixed(1)} GiB`;

        return `${Math.round(number)} MiB`;
    }

    function compactGpuName(value) {
        return String(value || "NVIDIA GPU").replace(/^NVIDIA\s+/i, "").replace(/^GeForce\s+/i, "");
    }

    function plainText(value) {
        return String(value ?? "").replace(/\r/g, "\n").replace(/<[^>]*>/g, "").trim();
    }

    function refresh() {
        if (!moduleVisible || refreshRunner.running)
            return;

        refreshRunner.exec(["/usr/bin/sh", "-lc", queryCommand]);
    }

    function applyOutput(output) {
        const trimmed = output.trim();
        if (trimmed.length === 0) {
            errorText = "No NVIDIA output";
            return;
        }

        const lines = trimmed.split("\n").map(line => line.trim()).filter(line => line.length > 0);
        const kernelLine = lines.find(line => line.startsWith(marker)) || "";
        const gpuLine = lines.find(line => !line.startsWith(marker)) || "";
        const parts = gpuLine.split(",").map(part => part.trim());

        kernelDriverVersion = kernelLine.slice(marker.length).trim();

        if (parts.length < 5) {
            errorText = plainText(gpuLine || trimmed);
            return;
        }

        const metrics = parts.slice(0, 3).map(value => value.length > 0 ? Number(value) : NaN);
        if (metrics.some(value => !Number.isFinite(value) || value < 0) || metrics[2] <= 0) {
            errorText = "GPU metrics unavailable: " + plainText(gpuLine);
            return;
        }

        utilization = ModuleData.clampPercent(metrics[0]);
        memoryUsed = metrics[1];
        memoryTotal = metrics[2];
        driverVersion = String(parts[3] || "").trim();
        gpuName = String(parts.slice(4).join(",") || "NVIDIA GPU").trim();
        errorText = "";
    }

    implicitWidth: compactContent.implicitWidth + 22
    implicitHeight: 34
    radius: 8
    color: mouse.containsMouse ? theme.surface2 : theme.alpha(theme.surface0, 0.28)
    border.color: root.hasError ? theme.alpha(theme.red, 0.72) : theme.alpha(theme.text, 0.1)
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
            id: statusLabel

            anchors.verticalCenter: parent.verticalCenter
            width: 28
            color: root.hasError ? theme.red : root.accent
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            horizontalAlignment: Text.AlignRight
            text: root.errorText.length > 0 ? "err" : `${Math.round(root.utilization).toString().padStart(2, " ")}%`
            textFormat: Text.PlainText
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: root.accent
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: root.hasError ? "" : "󰢮"
            textFormat: Text.PlainText
        }
    }

    BarPopup {
        id: tooltipWindow

        barWindow: root.barWindow
        anchorItem: root
        shown: root.tooltipVisible
        implicitWidth: 360
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
                        text: root.hasError ? "" : "󰢮"
                    }

                    Column {
                        width: parent.width - 30
                        spacing: 2

                        Text {
                            width: parent.width
                            color: theme.text
                            elide: Text.ElideRight
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize + 1
                            font.bold: true
                            text: root.compactGpuName(root.gpuName)
                        }

                        Text {
                            width: parent.width
                            color: root.hasError ? theme.red : theme.subtext0
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize
                            text: root.driverMismatch ? "Driver mismatch: reboot required" : root.driverVersion.length > 0 ? `Driver ${root.driverVersion}` : "Driver unknown"
                        }
                    }
                }

                Text {
                    visible: root.errorText.length > 0
                    width: parent.width
                    color: theme.red
                    font.family: theme.fontFamily
                    font.pixelSize: theme.tooltipFontPixelSize
                    text: root.errorText
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                }

                Column {
                    visible: root.driverMismatch
                    width: parent.width
                    spacing: 2

                    Text {
                        width: parent.width
                        color: theme.red
                        font.family: theme.fontFamily
                        font.pixelSize: theme.tooltipFontPixelSize
                        text: "Installed NVIDIA userspace and loaded kernel module differ. Reboot after upgrade."
                        wrapMode: Text.Wrap
                    }

                    Text {
                        width: parent.width
                        color: theme.subtext0
                        font.family: theme.fontFamily
                        font.pixelSize: theme.tooltipFontPixelSize
                        text: `nvidia-smi ${root.driverVersion} / kernel ${root.kernelDriverVersion || "unknown"}`
                    }
                }

                MetricBar {
                    width: parent.width
                    visible: root.errorText.length === 0
                    label: "GPU"
                    percent: root.utilization
                    valueText: `${Math.round(root.utilization)}% util`
                    accent: root.accent
                    fillColor: theme.alpha(String(root.accent), 0.38)
                }

                MetricBar {
                    width: parent.width
                    visible: root.errorText.length === 0
                    label: "VRAM"
                    percent: root.memoryPercent
                    valueText: `${root.mibText(root.memoryUsed)} / ${root.mibText(root.memoryTotal)}`
                    accent: root.memoryPercent >= 90 ? theme.yellow : theme.sky
                    fillColor: theme.alpha(root.memoryPercent >= 90 ? theme.yellow : theme.sky, 0.34)
                }
            }
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

    Connections {
        target: root.ipc
        function onRefreshRequested(name) {
            if (name === "gpu" || name === "all")
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
