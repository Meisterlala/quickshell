pragma ComponentBehavior: Bound

import ".."
import "../components"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Quickshell.Wayland

Rectangle {
    id: root

    required property var barWindow
    // Add lowercase tray ids or titles here, for example: "steam".
    property var ignoredTrayItems: ["udiskie"]
    property var openItem: null
    readonly property bool hasVisibleItems: trayRow.implicitWidth > 0

    function itemField(item, field) {
        try {
            const value = item[field];
            return value === undefined || value === null ? "" : String(value);
        } catch (error) {
            return "";
        }
    }

    function trayField(item, field) {
        return itemField(item, field).toLowerCase();
    }

    function isIgnored(item) {
        const values = [trayField(item, "id"), trayField(item, "title"), trayField(item, "tooltipTitle"), trayField(item, "name")];
        return ignoredTrayItems.some(ignored => values.includes(String(ignored).toLowerCase()));
    }

    implicitWidth: hasVisibleItems ? trayRow.implicitWidth + 16 : 0
    implicitHeight: 34
    radius: 8
    color: hasVisibleItems ? trayTheme.alpha(trayTheme.surface0, 0.28) : "transparent"
    border.color: hasVisibleItems ? trayTheme.alpha(trayTheme.text, 0.1) : "transparent"
    border.width: hasVisibleItems ? 1 : 0

    Theme { id: trayTheme }

    // Layer-shell popups inherit keyboard interactivity from their parent bar.
    Binding {
        target: root.barWindow ? root.barWindow.WlrLayershell : null
        property: "keyboardFocus"
        value: WlrKeyboardFocus.OnDemand
        when: !!root.openItem
        restoreMode: Binding.RestoreBindingOrValue
    }

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: SystemTray.items

            Item {
                id: trayItem

                required property var modelData
                readonly property bool ignored: root.isIgnored(modelData)
                readonly property string tooltipTitle: root.itemField(modelData, "tooltipTitle") || root.itemField(modelData, "title") || root.itemField(modelData, "name") || root.itemField(modelData, "id")
                readonly property string tooltipDescription: root.itemField(modelData, "tooltipDescription") || root.itemField(modelData, "tooltip")
                readonly property string tooltipText: tooltipDescription.length > 0 && tooltipDescription !== tooltipTitle ? tooltipTitle + "\n" + tooltipDescription : tooltipTitle
                readonly property bool menuOpen: root.openItem === trayItem
                Component.onDestruction: {
                    if (root.openItem === trayItem)
                        root.openItem = null;
                }

                function displayMenu() {
                    if (modelData.hasMenu)
                        root.openItem = menuOpen ? null : trayItem;
                }

                visible: !ignored
                width: ignored ? 0 : 24
                height: ignored ? 0 : 34

                IconImage {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    source: trayItem.modelData.icon
                }

                MouseArea {
                    id: iconMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    hoverEnabled: true
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton && !trayItem.modelData.onlyMenu)
                            trayItem.modelData.activate();
                        else if (mouse.button === Qt.MiddleButton)
                            trayItem.modelData.secondaryActivate();
                        else
                            trayItem.displayMenu();
                    }
                }

                PopupWindow {
                    id: tooltipWindow
                    readonly property int margin: 8
                    readonly property int maxTooltipWidth: root.barWindow ? Math.min(420, Math.max(180, root.barWindow.width - margin * 2)) : 300

                    anchor.window: root.barWindow
                    anchor.edges: Edges.Top | Edges.Left
                    anchor.gravity: Edges.Bottom | Edges.Right
                    anchor.adjustment: PopupAdjustment.SlideX
                    anchor.rect.x: root.barWindow ? Math.max(margin, Math.min(root.barWindow.width - width - margin, trayItem.mapToItem(null, 0, 0).x + trayItem.width / 2 - width / 2)) : 0
                    anchor.rect.y: root.barWindow ? root.barWindow.height + margin : trayItem.height + margin
                    anchor.rect.width: trayItem.width
                    anchor.rect.height: trayItem.height
                    implicitWidth: Math.min(maxTooltipWidth, tooltipLabel.implicitWidth + 28)
                    implicitHeight: tooltipLabel.implicitHeight + 20
                    color: "transparent"
                    grabFocus: false
                    visible: root.barWindow && !trayItem.ignored && !root.openItem && iconMouse.containsMouse && trayItem.tooltipText.length > 0

                    PopupSurface {
                        anchors.fill: parent
                        clip: true

                        Text {
                            id: tooltipLabel
                            anchors.fill: parent
                            anchors.margins: 10
                            text: trayItem.tooltipText
                            color: trayTheme.text
                            font.family: trayTheme.fontFamily
                            font.pixelSize: trayTheme.tooltipFontPixelSize
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                        }
                    }
                }

                TrayMenu {
                    menu: trayItem.modelData.menu
                    anchorHovered: iconMouse.containsMouse
                    anchor.window: root.barWindow
                    anchor.rect.x: root.barWindow ? Math.max(8, Math.min(root.barWindow.width - width - 8, trayItem.mapToItem(null, 0, 0).x)) : 0
                    anchor.rect.y: root.barWindow ? root.barWindow.height + 8 : 0
                    anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.SlideY
                    visible: !!root.barWindow && !trayItem.ignored && trayItem.menuOpen
                    onDismissed: {
                        if (root.openItem === trayItem)
                            root.openItem = null;
                    }
                }
            }
        }
    }
}
