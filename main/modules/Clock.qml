import "../components"
import "../popups"
import ".."
import QtQuick
import Quickshell

Item {
    id: root

    required property var barWindow
    property var ipc: null
    property bool popupIpcEnabled: true
    property bool alternativeMode: false
    property bool popupOpen: false
    property bool popupPinned: false
    signal alternativeModeToggled()

    function updateHover() {
        if (pill.hovered || popupHover.hovered || popupPinned) {
            hideDelay.stop();
            popupOpen = true;
        } else {
            hideDelay.restart();
        }
    }

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Timer {
        id: hideDelay
        interval: 300 // Allow the pointer to cross the gap below the bar.
        onTriggered: {
            if (!pill.hovered && !popupHover.hovered && !root.popupPinned)
                root.popupOpen = false;
        }
    }

    ModulePill {
        id: pill

        barWindow: root.barWindow
        text: Qt.formatDateTime(clock.date, "hh:mm") + " "
        moduleClass: root.alternativeMode ? "warning" : ""
        onHoveredChanged: root.updateHover()
        onClicked: (button) => {
            if (button === Qt.MiddleButton) {
                root.alternativeModeToggled();
                root.popupPinned = false;
                root.popupOpen = false;
            } else {
                root.popupPinned = !root.popupPinned;
                root.updateHover();
            }
        }
    }

    Connections {
        target: root.ipc
        function onRefreshRequested(name) {
            if ((name === "calendar" || name === "all") && calendarLoader.item)
                calendarLoader.item.refresh();
        }
        function onPopupRequested(name) {
            if (name === "calendar" && root.popupIpcEnabled) {
                root.popupPinned = !root.popupPinned;
                root.updateHover();
            }
        }
    }

    PopupWindow {
        anchor.window: root.barWindow
        anchor.rect.x: root.barWindow ? root.barWindow.width - width - 8 : 0
        anchor.rect.y: root.barWindow ? root.barWindow.height + 8 : 0
        implicitWidth: 380
        implicitHeight: calendarLoader.item ? calendarLoader.item.implicitHeight : 500
        color: "transparent"
        visible: root.popupOpen
        grabFocus: false
        onVisibleChanged: {
            if (!visible) {
                root.popupOpen = false;
                root.popupPinned = false;
            }
        }

        Loader {
            id: calendarLoader
            anchors.fill: parent
            active: root.popupOpen
            HoverHandler {
                id: popupHover
                onHoveredChanged: root.updateHover()
            }
            sourceComponent: CalendarPopup {
                today: clock.date
            }
        }

    }

}
