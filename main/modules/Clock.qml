import "../components"
import QtQuick
import Quickshell

Item {
    id: root

    required property var barWindow
    property bool popupOpen: false

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    ModulePill {
        id: pill

        text: Qt.formatDateTime(clock.date, "hh:mm") + " "
        onClicked: root.popupOpen = !root.popupOpen
    }

    PopupWindow {
        anchor.window: root.barWindow
        anchor.rect.x: root.barWindow.width - width - 8
        anchor.rect.y: root.barWindow.height + 8
        implicitWidth: 320
        implicitHeight: 250
        visible: root.popupOpen
        grabFocus: true
        onVisibleChanged: {
            if (!visible)
                root.popupOpen = false;

        }

        PopupSurface {
            anchors.fill: parent

            Column {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Text {
                    text: Qt.formatDateTime(clock.date, "dddd, dd.MM.yyyy")
                    color: "#cdd6f4"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 18
                }

                Text {
                    text: Qt.formatDateTime(clock.date, "hh:mm")
                    color: "#f5e0dc"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 44
                    font.bold: true
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#3345475a"
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Calendar grid and agenda go here next. This popup is already anchored to the clock and managed by Quickshell, not a Waybar tooltip."
                    color: "#a6adc8"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 13
                }

            }

        }

    }

}
