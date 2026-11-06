pragma ComponentBehavior: Bound

import "../components"
import ".."
import QtQuick
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
    property string actionError: ""
    readonly property int systemCount: systemUnits.length
    readonly property int userCount: userUnits.length
    readonly property int totalCount: systemCount + userCount
    readonly property bool tooltipVisible: mouse.containsMouse

    function refresh() {
        if (!moduleVisible || refreshRunner.running)
            return;

        refreshRunner.run();
    }

    function runRestart() {
        if (actionRunner.running)
            return;
        actionError = "";
        actionRunner.run(["restart"]);
    }

    function applyOutput(output) {
        try {
            const data = JSON.parse(output);
            if (!data || typeof data.error !== "string" || !(data.systemUnits === null || Array.isArray(data.systemUnits)) || !(data.userUnits === null || Array.isArray(data.userUnits)) || ((data.systemUnits === null || data.userUnits === null) && !data.error))
                throw new Error("Invalid service response");
            if (Array.isArray(data.systemUnits))
                systemUnits = data.systemUnits;
            if (Array.isArray(data.userUnits))
                userUnits = data.userUnits;
            errorText = String(data.error || "");
        } catch (error) {
            errorText = "Unable to read failed systemd services";
        }
    }

    implicitWidth: compactContent.implicitWidth + 20
    implicitHeight: 34
    radius: 8
    color: mouse.containsMouse ? theme.surface2 : theme.alpha(theme.surface0, 0.28)
    border.color: theme.alpha(theme.red, 0.72)
    border.width: 1
    contentUnderBorder: true
    visible: moduleVisible && (totalCount > 0 || errorText.length > 0 || actionError.length > 0)

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
            text: root.totalCount > 0 ? String(root.totalCount) : "err"
            textFormat: Text.PlainText
        }
    }

    BarPopup {
        id: tooltipWindow

        barWindow: root.barWindow
        anchorItem: root
        shown: root.tooltipVisible
        implicitWidth: 360
        implicitHeight: Math.min(480, detailsColumn.implicitHeight + 28)

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
                                text: root.errorText ? "Service check failed" : `${root.totalCount} failed systemd service${root.totalCount === 1 ? "" : "s"}`
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

                    Text {
                        width: parent.width
                        visible: root.errorText.length > 0 || root.actionError.length > 0
                        text: [root.errorText, root.actionError].filter(value => value.length > 0).join("\n")
                        color: theme.red
                        font.family: theme.fontFamily
                        font.pixelSize: theme.tooltipFontPixelSize
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
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
        onClicked: event => {
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

    HelperProcess {
        id: refreshRunner
        helper: "systemd-failed-units"
        onOutput: text => root.applyOutput(text)
    }

    HelperProcess {
        id: actionRunner
        helper: "systemd-failed-units"
        onExited: exitCode => {
            root.actionError = exitCode === 0 ? "" : actionRunner.errorText.trim() || "Service restart failed";
            root.refresh();
        }
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
