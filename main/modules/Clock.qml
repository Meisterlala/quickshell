import "../components"
import ".."
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

    Theme {
        id: theme
    }

    ModulePill {
        id: pill

        barWindow: root.barWindow
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
                    color: theme.text
                    font.family: theme.fontFamily
                    font.pixelSize: theme.popupTitleFontPixelSize
                }

                Text {
                    text: Qt.formatDateTime(clock.date, "hh:mm")
                    color: theme.rosewater
                    font.family: theme.fontFamily
                    font.pixelSize: theme.popupLargeFontPixelSize
                    font.bold: true
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#3345475a"
                }

            }

        }

    }

}
