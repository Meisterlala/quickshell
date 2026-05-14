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
    property int interval: 900000
    property string moduleName: "updates"
    property string command: "/home/misti/.config/quickshell/main/scripts/arch_updates.py"
    property string updateCommand: "ghostty -e bash -lc 'paru -Syu; echo; read -rp \"Press Enter to close...\"'"
    property int count: 0
    property string state: "updated"
    property var counts: ({})
    property var items: []
    property int truncated: 0
    property string errorText: ""
    property bool stale: false
    property string status: "ok"
    readonly property bool hasUpdates: count > 0
    readonly property bool hasError: errorText.length > 0 || state === "error"
    readonly property string accent: hasError ? theme.red : state === "critical" ? theme.red : state === "warning" ? theme.yellow : theme.sky
    readonly property bool tooltipVisible: mouse.containsMouse

    function sourceColor(source) {
        if (source === "core")
            return theme.red;
        if (source === "extra")
            return theme.sky;
        if (source === "multilib")
            return theme.rosewater;
        if (source === "aur")
            return theme.yellow;
        if (source === "devel")
            return "#fab387";
        return theme.subtext0;
    }

    function sourceCount(source) {
        return Number((counts || {})[source] || 0);
    }

    function visibleSources() {
        const order = ["core", "extra", "multilib", "aur", "devel"];
        const result = [];
        for (const source of order) {
            if (sourceCount(source) > 0)
                result.push(source);
        }
        for (const source of Object.keys(counts || {}).sort()) {
            if (order.indexOf(source) < 0 && sourceCount(source) > 0)
                result.push(source);
        }
        return result;
    }

    function refresh() {
        if (!moduleVisible)
            return;

        refreshRunner.exec(["/usr/sbin/python3", command]);
    }

    function runUpdate() {
        actionRunner.exec(["/usr/sbin/sh", "-lc", updateCommand]);
    }

    function applyOutput(output) {
        const trimmed = output.trim();
        if (trimmed.length === 0) {
            errorText = "No update output";
            state = "error";
            return;
        }

        try {
            const lines = trimmed.split("\n").filter(line => line.trim().length > 0);
            const parsed = JSON.parse(lines[lines.length - 1]);
            count = Number(parsed.count || 0);
            state = String(parsed.state || "normal");
            counts = parsed.counts || ({});
            items = parsed.items || [];
            truncated = Number(parsed.truncated || 0);
            stale = Boolean(parsed.stale || false);
            status = String(parsed.status || "ok");
            errorText = String(parsed.error || "").trim();
        } catch (error) {
            errorText = trimmed;
            state = "error";
        }
    }

    function scrollList(delta) {
        if (!tooltipVisible)
            return;

        const maxY = Math.max(0, listFlickable.contentHeight - listFlickable.height);
        listFlickable.contentY = Math.max(0, Math.min(maxY, listFlickable.contentY - delta));
    }

    implicitWidth: compactContent.implicitWidth + 20
    implicitHeight: 34
    radius: 8
    color: mouse.containsMouse ? theme.surface2 : theme.alpha(theme.surface0, 0.28)
    border.color: hasError ? theme.alpha(theme.red, 0.72) : theme.alpha(theme.text, 0.1)
    border.width: 1
    contentUnderBorder: true
    visible: moduleVisible && (hasUpdates || hasError)

    Theme {
        id: theme
    }

    Row {
        id: compactContent

        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: root.hasError ? "err" : String(root.count)
            textFormat: Text.PlainText
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: root.hasError ? "" : "󱍷"
            textFormat: Text.PlainText
        }
    }

    PopupWindow {
        id: tooltipWindow

        readonly property int margin: 8
        readonly property int maxTooltipHeight: root.barWindow && root.barWindow.screen ? Math.max(180, Math.round((root.barWindow.screen.height - root.barWindow.height - margin * 2) * 0.75)) : 520

        anchor.window: root.barWindow
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeY
        anchor.rect.x: root.barWindow ? Math.max(margin, Math.min(root.barWindow.width - width - margin, root.mapToItem(null, 0, 0).x + root.width / 2 - width / 2)) : 0
        anchor.rect.y: root.barWindow ? root.barWindow.height + margin : root.height + margin
        anchor.rect.width: root.width
        anchor.rect.height: root.height
        implicitWidth: 720
        implicitHeight: Math.min(maxTooltipHeight, headerColumn.implicitHeight + listFlickable.height + 28)
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

                Column {
                    id: headerColumn

                    width: parent.width
                    spacing: 10

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            color: theme.text
                            font.family: theme.fontFamily
                            font.pixelSize: theme.barFontPixelSize + 3
                            text: root.hasError ? "" : "󱍷"
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
                                text: root.hasError ? "Update check failed" : `${root.count} package update${root.count === 1 ? "" : "s"}`
                            }

                            Text {
                                width: parent.width
                                color: theme.subtext0
                                font.family: theme.fontFamily
                                font.pixelSize: theme.tooltipFontPixelSize
                                text: root.stale ? "Last known state while updates are running" : "Left-click to run paru -Syu"
                            }
                        }
                    }

                    Text {
                        visible: root.hasError
                        width: parent.width
                        color: theme.red
                        font.family: theme.fontFamily
                        font.pixelSize: theme.tooltipFontPixelSize
                        text: root.errorText
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }

                    Row {
                        visible: !root.hasError
                        width: parent.width
                        spacing: 10

                        Repeater {
                            model: root.visibleSources()

                            SourceChip {
                                required property string modelData

                                label: modelData
                                count: root.sourceCount(modelData)
                                accent: root.sourceColor(modelData)
                            }
                        }
                    }

                    Rectangle {
                        visible: !root.hasError && root.items.length > 0
                        width: parent.width
                        height: 1
                        color: theme.alpha(theme.text, 0.1)
                    }
                }

                Flickable {
                    id: listFlickable

                    visible: !root.hasError
                    width: parent.width
                    height: Math.max(0, Math.min(listColumn.implicitHeight, tooltipWindow.maxTooltipHeight - headerColumn.implicitHeight - 28))
                    contentWidth: width
                    contentHeight: listColumn.implicitHeight
                    clip: true

                    Column {
                        id: listColumn

                        width: parent.width
                        spacing: 1

                        Repeater {
                            model: root.items

                            UpdateRow {
                                required property var modelData

                                width: detailsColumn.width
                                source: String(modelData.source || "repo")
                                packageName: String(modelData.name || "")
                                oldVersion: String(modelData.old || "")
                                newVersion: String(modelData.new || "")
                            }
                        }

                        Text {
                            visible: root.truncated > 0
                            width: parent.width
                            color: theme.subtext0
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize
                            text: `... and ${root.truncated} more`
                        }
                    }
                }
            }
        }
    }

    component SourceChip: Rectangle {
        id: chipRoot

        required property string label
        required property int count
        required property string accent

        implicitWidth: chipText.implicitWidth + 14
        implicitHeight: 22
        radius: 7
        color: theme.alpha(String(accent), 0.16)
        border.color: theme.alpha(String(accent), 0.35)
        border.width: 1

        Text {
            id: chipText

            anchors.centerIn: parent
            color: chipRoot.accent
            font.family: theme.fontFamily
            font.pixelSize: 11
            text: `${chipRoot.label}: ${chipRoot.count}`
        }
    }

    component UpdateRow: Item {
        id: rowRoot

        required property string source
        required property string packageName
        required property string oldVersion
        required property string newVersion

        height: 16

        Text {
            id: sourceLabel

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 102
            color: root.sourceColor(rowRoot.source)
            font.family: theme.fontFamily
            font.pixelSize: 11
            text: rowRoot.source
            textFormat: Text.PlainText
        }

        Text {
            id: packageLabel

            anchors.left: sourceLabel.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(80, parent.width - sourceLabel.width - 280))
            color: theme.text
            elide: Text.ElideRight
            font.family: theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            text: rowRoot.packageName
            textFormat: Text.PlainText
        }

        Text {
            id: versionLabel

            anchors.left: packageLabel.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: theme.subtext0
            elide: Text.ElideLeft
            font.family: theme.fontFamily
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
            text: `${rowRoot.oldVersion} -> ${rowRoot.newVersion}`
            textFormat: Text.PlainText
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        z: 10
        onClicked: (event) => {
            if (event.button === Qt.LeftButton)
                root.runUpdate();
            else if (event.button === Qt.RightButton)
                root.refresh();

        }
        onContainsMouseChanged: {
            if (containsMouse)
                root.refresh();

        }
        onWheel: (wheel) => {
            root.scrollList(wheel.angleDelta.y);
            wheel.accepted = true;
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

    Connections {
        function onRefreshRequested(name) {
            if (name === root.moduleName || name === "all")
                root.refresh();
        }

        target: root.ipc
    }

    Component.onCompleted: refresh()
    onModuleVisibleChanged: {
        if (moduleVisible)
            refresh();
        else {
            count = 0;
            items = [];
            counts = ({});
            stale = false;
            status = "ok";
            errorText = "";
        }
    }
}
