pragma ComponentBehavior: Bound

import ".."
import "../components"
import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

PopupSurface {
    id: root
    required property var service
    property var controls: ({ inhibited: false, monitor: "unknown" })
    property string controlError: ""
    implicitHeight: topContent.implicitHeight + 32 + (service.history.length ? 12 + list.contentHeight : 0)
    color: theme.alpha(theme.mantle, 0.98)
    radius: 16

    function refreshControls(action) {
        if (!controlReader.running)
            controlReader.exec(["python3", Quickshell.shellPath("scripts/notification_controls.py"), action || "status"]);
    }

    Component.onCompleted: refreshControls("status")

    Theme { id: theme }
    Process {
        id: controlReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.controlError = result.error || "";
                    if (!root.controlError)
                        root.controls = result;
                } catch (error) {
                    root.controlError = "Could not read control state";
                }
            }
        }
    }
    Timer {
        interval: 5000
        repeat: true
        running: root.visible
        onTriggered: root.refreshControls("status")
    }
    MouseArea {
        id: contextMouse
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: {
            contextMenu.x = mouseX;
            contextMenu.y = mouseY;
            contextMenu.open();
        }
    }
    Controls.Menu {
        id: contextMenu
        onAboutToShow: root.refreshControls("status")
        Controls.MenuItem {
            text: "Do not disturb"
            checkable: true
            checked: root.service.doNotDisturb
            onTriggered: root.service.setDnd(!root.service.doNotDisturb)
        }
        Controls.MenuItem {
            text: "Always on Top"
            checkable: true
            checked: root.service.alwaysOnTop
            onTriggered: root.service.setAlwaysOnTop(!root.service.alwaysOnTop)
        }
        Controls.MenuItem {
            text: "Stay awake"
            checkable: true
            checked: !!root.controls.inhibited
            enabled: !controlReader.running
            onTriggered: root.refreshControls("idle")
        }
        Controls.MenuItem {
            text: "Second monitor off"
            checkable: true
            checked: root.controls.monitor === "off"
            enabled: !controlReader.running && ["on", "off"].includes(root.controls.monitor)
            onTriggered: root.refreshControls("monitor")
        }
        Controls.MenuSeparator {}
        Controls.MenuItem {
            text: "Clear all notifications"
            enabled: root.service.entries.length > 0
            onTriggered: root.service.clear()
        }
    }

    Column {
        id: topContent
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 12
        Flow {
            width: parent.width
            spacing: 6
            NotificationButton {
                icon: root.service.doNotDisturb ? "󰂛" : "󰂚"
                text: "DND"
                checked: root.service.doNotDisturb
                onClicked: root.service.setDnd(!root.service.doNotDisturb)
            }
            NotificationButton {
                text: "Always on Top"
                checked: root.service.alwaysOnTop
                onClicked: root.service.setAlwaysOnTop(!root.service.alwaysOnTop)
            }
            NotificationButton {
                icon: "󰒲"
                text: "Stay awake"
                checked: !!root.controls.inhibited
                enabled: !controlReader.running
                onClicked: root.refreshControls("idle")
            }
            NotificationButton {
                icon: "󰍹"
                text: "Screen 2" + (["on", "off"].includes(root.controls.monitor) ? " " + root.controls.monitor : "")
                checked: root.controls.monitor === "off"
                enabled: !controlReader.running && ["on", "off"].includes(root.controls.monitor)
                onClicked: root.refreshControls("monitor")
            }
            NotificationButton {
                text: "Clear"
                enabled: root.service.entries.length > 0
                onClicked: root.service.clear()
            }
        }
        Text {
            width: parent.width
            visible: text.length > 0
            text: root.controlError || root.service.persistenceError
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.red
            font.pixelSize: 12
        }
        // Native MPRIS subscriptions replace SwayNC's media widget. No polling.
        Column {
            width: parent.width
            spacing: 6
            Repeater {
                model: Mpris.players
                Rectangle {
                    id: playerCard
                    required property var modelData
                    width: parent.width
                    height: 66
                    color: theme.surface0
                    radius: 10
                    Text {
                        x: 10
                        y: 8
                        width: parent.width - mediaButtons.width - 24
                        text: playerCard.modelData.trackTitle || playerCard.modelData.identity
                        textFormat: Text.PlainText
                        color: theme.text
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                    Text {
                        x: 10
                        y: 34
                        width: parent.width - mediaButtons.width - 24
                        text: playerCard.modelData.trackArtist || playerCard.modelData.identity
                        textFormat: Text.PlainText
                        color: theme.subtext0
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Row {
                        id: mediaButtons
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        NotificationButton {
                            icon: "󰒮"
                            enabled: playerCard.modelData.canGoPrevious
                            onClicked: playerCard.modelData.previous()
                        }
                        NotificationButton {
                            icon: playerCard.modelData.isPlaying ? "󰏤" : "󰐊"
                            enabled: playerCard.modelData.canTogglePlaying
                            onClicked: playerCard.modelData.togglePlaying()
                        }
                        NotificationButton {
                            icon: "󰒭"
                            enabled: playerCard.modelData.canGoNext
                            onClicked: playerCard.modelData.next()
                        }
                    }
                }
            }
        }
        Rectangle {
            visible: Mpris.players.values.length > 0 && root.service.history.length > 0
            width: parent.width
            height: 1
            color: theme.surface1
        }
        Text {
            visible: root.service.history.length === 0 && Mpris.players.values.length === 0
            text: "No notifications"
            color: theme.subtext0
            font.family: theme.fontFamily
            font.pixelSize: 12
        }
    }

    ListView {
        id: list
        anchors.top: topContent.bottom
        anchors.topMargin: root.service.history.length ? 12 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        spacing: 8
        clip: true
        model: root.service.history
        boundsBehavior: Flickable.StopAtBounds
        delegate: NotificationCard {
            required property var modelData
            width: list.width
            entry: modelData
            service: root.service
        }
    }
}
