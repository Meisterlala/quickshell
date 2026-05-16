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
    property string moduleName: "systemd-failed-units"
    property var systemUnits: []
    property var userUnits: []
    property string errorText: ""
    readonly property string queryCommand: "export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus; systemctl --failed --type=service --no-legend --plain 2>/dev/null | while read -r unit rest; do [ -n \"$unit\" ] && printf 'system\\t%s\\n' \"$unit\"; done; systemctl --user --failed --type=service --no-legend --plain 2>/dev/null | while read -r unit rest; do [ -n \"$unit\" ] && printf 'user\\t%s\\n' \"$unit\"; done"
    readonly property string restartCommand: "/home/misti/.config/quickshell/main/scripts/restart_failed_units.sh"
    readonly property int systemCount: systemUnits.length
    readonly property int userCount: userUnits.length
    readonly property int totalCount: systemCount + userCount
    readonly property bool tooltipVisible: mouse.containsMouse

    function refresh() {
        if (!moduleVisible)
            return;

        refreshRunner.exec(["/usr/bin/sh", "-lc", queryCommand]);
    }

    function runRestart() {
        actionRunner.exec([restartCommand]);
    }

    function applyOutput(output) {
        const nextSystem = [];
        const nextUser = [];
        const trimmed = output.trim();

        if (trimmed.length > 0) {
            for (const line of trimmed.split("\n")) {
                const parts = line.trim().split("\t");
                if (parts.length < 2 || parts[1].length === 0)
                    continue;

                if (parts[0] === "system")
                    nextSystem.push(parts[1]);
                else if (parts[0] === "user")
                    nextUser.push(parts[1]);
            }
        }

        systemUnits = nextSystem;
        userUnits = nextUser;
        errorText = "";
    }

    implicitWidth: compactContent.implicitWidth + 20
    implicitHeight: 34
    radius: 8
    color: mouse.containsMouse ? theme.surface2 : theme.alpha(theme.surface0, 0.28)
    border.color: theme.alpha(theme.red, 0.72)
    border.width: 1
    contentUnderBorder: true
    visible: moduleVisible && (totalCount > 0 || errorText.length > 0)

    Theme {
        id: theme
    }

    Row {
        id: compactContent

        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: theme.red
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: ""
            textFormat: Text.PlainText
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: theme.red
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: String(totalCount)
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
        implicitWidth: 360
        implicitHeight: Math.min(480, detailsColumn.implicitHeight + 28)
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
                    spacing: 10

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            color: theme.red
                            font.family: theme.fontFamily
                            font.pixelSize: theme.barFontPixelSize + 3
                            text: ""
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
                                text: `${root.totalCount} failed systemd service${root.totalCount === 1 ? "" : "s"}`
                            }

                            Text {
                                width: parent.width
                                color: theme.subtext0
                                font.family: theme.fontFamily
                                font.pixelSize: theme.tooltipFontPixelSize
                                text: "Left-click to restart, right-click to refresh"
                            }
                        }
                    }

                    UnitSection {
                        width: parent.width
                        visible: root.systemCount > 0
                        title: `System services (${root.systemCount})`
                        units: root.systemUnits
                    }

                    UnitSection {
                        width: parent.width
                        visible: root.userCount > 0
                        title: `User services (${root.userCount})`
                        units: root.userUnits
                    }
                }
            }
        }
    }

    component UnitSection: Column {
        id: sectionRoot

        required property string title
        required property var units

        spacing: 4

        Text {
            width: parent.width
            color: theme.red
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize
            font.bold: true
            text: sectionRoot.title
        }

        Repeater {
            model: sectionRoot.units

            Text {
                required property string modelData

                width: sectionRoot.width
                color: theme.text
                elide: Text.ElideRight
                font.family: theme.fontFamily
                font.pixelSize: theme.tooltipFontPixelSize
                text: modelData
                textFormat: Text.PlainText
            }
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
                root.runRestart();
            else if (event.button === Qt.RightButton)
                root.refresh();

        }
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
            systemUnits = [];
            userUnits = [];
            errorText = "";
        }
    }
}
