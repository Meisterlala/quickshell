import "../components"
import ".."
import QtQuick

ModulePill {
    id: root
    required property var service
    property bool moduleVisible: true
    readonly property bool hasUnread: service.unreadCount > 0

    text: service.doNotDisturb ? (hasUnread ? "󰂠" : "󰪓") : (hasUnread ? "󱅫" : "󰂜")
    tooltipText: `${service.unreadCount} unread · ${service.history.length} saved`
    moduleClass: service.doNotDisturb ? "warning" : ""
    visible: moduleVisible
    backgroundVisible: false
    fontPixelSize: theme.notificationFontPixelSize
    horizontalPadding: 4
    minimumWidth: 26
    onClicked: button => {
        if (button === Qt.LeftButton)
            service.toggleCenter(barWindow && barWindow.screen ? barWindow.screen.name : "");
        else if (button === Qt.RightButton)
            service.setDnd(!service.doNotDisturb);
        else if (button === Qt.MiddleButton)
            service.clear();
    }
    Theme { id: theme }
}
