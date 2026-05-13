import ".."
import "../components"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Rectangle {
    // Add lowercase tray ids or titles here, for example: "steam"

    id: root

    required property var barWindow
    property var ignoredTrayItems: ["udiskie"]
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
        return ignoredTrayItems.some((ignored) => {
            return values.includes(String(ignored).toLowerCase());
        });
    }

    implicitWidth: hasVisibleItems ? trayRow.implicitWidth + 16 : 0
    implicitHeight: 34
    radius: 8
    color: hasVisibleItems ? trayTheme.alpha(trayTheme.surface0, 0.28) : "transparent"
    border.color: hasVisibleItems ? trayTheme.alpha(trayTheme.text, 0.1) : "transparent"
    border.width: hasVisibleItems ? 1 : 0

    Theme {
        id: trayTheme
    }

    Row {
        id: trayRow

        anchors.centerIn: parent
        spacing: 8

        Repeater {
            id: trayRepeater

            model: SystemTray.items

            Item {
                id: trayItem

                required property var modelData
                readonly property bool ignored: root.isIgnored(modelData)
                readonly property string tooltipTitle: root.itemField(modelData, "tooltipTitle") || root.itemField(modelData, "title") || root.itemField(modelData, "name") || root.itemField(modelData, "id")
                readonly property string tooltipDescription: root.itemField(modelData, "tooltipDescription") || root.itemField(modelData, "tooltip")
                readonly property string tooltipText: tooltipDescription.length > 0 && tooltipDescription !== tooltipTitle ? tooltipTitle + "\n" + tooltipDescription : tooltipTitle
                property bool menuOpen: false

                function displayMenu() {
                    if (!modelData.hasMenu)
                        return ;

                    menuOpen = !menuOpen;
                }

                visible: !ignored
                width: ignored ? 0 : 24
                height: ignored ? 0 : 34

                IconImage {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    source: modelData.icon
                }

                MouseArea {
                    id: iconMouse

                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    hoverEnabled: true
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton && !modelData.onlyMenu)
                            modelData.activate();
                        else if (mouse.button === Qt.MiddleButton)
                            modelData.secondaryActivate();
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
                    visible: root.barWindow && !trayItem.ignored && !trayItem.menuOpen && iconMouse.containsMouse && trayItem.tooltipText.length > 0

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

                PopupWindow {
                    id: menuWindow

                    readonly property int outerMargin: 8
                    readonly property int horizontalMargin: 4
                    readonly property int entryHorizontalPadding: 12
                    readonly property int entrySpacing: 8
                    readonly property int entryHeight: 30
                    readonly property int separatorWidth: 164
                    readonly property int separatorHeight: 9
                    readonly property int iconSize: 16
                    readonly property int targetWidth: Math.round(root.barWindow.width * 0.33)
                    readonly property int maxTextWidth: targetWidth - outerMargin * 2 - entryHorizontalPadding * 2

                    anchor.window: root.barWindow
                    anchor.rect.x: Math.max(outerMargin, Math.min(root.barWindow.width - width - outerMargin, trayItem.mapToItem(null, 0, 0).x))
                    anchor.rect.y: root.barWindow.height + outerMargin
                    implicitWidth: Math.max(220, Math.min(targetWidth, menuContent.implicitWidth + horizontalMargin * 2))
                    implicitHeight: menuContent.implicitHeight + outerMargin * 2
                    color: "transparent"
                    visible: !trayItem.ignored && trayItem.menuOpen
                    grabFocus: true
                    onVisibleChanged: {
                        if (!visible)
                            trayItem.menuOpen = false;

                    }

                    PopupSurface {
                        anchors.fill: parent

                        Column {
                            id: menuContent

                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: menuWindow.outerMargin
                            anchors.bottomMargin: menuWindow.outerMargin
                            anchors.leftMargin: menuWindow.horizontalMargin
                            anchors.rightMargin: menuWindow.horizontalMargin

                            Repeater {
                                model: menuOpener.children

                                Rectangle {
                                    id: menuEntry

                                    required property var modelData
                                    readonly property bool hasCheckmark: modelData.checkState === Qt.Checked
                                    readonly property bool hasIcon: modelData.icon.length > 0
                                    readonly property int leadingWidth: (hasCheckmark ? checkmark.implicitWidth + menuWindow.entrySpacing : 0) + (hasIcon ? menuWindow.iconSize + menuWindow.entrySpacing : 0)
                                    readonly property int trailingWidth: modelData.hasChildren ? menuWindow.entrySpacing + arrow.implicitWidth : 0

                                    implicitWidth: modelData.isSeparator ? menuWindow.separatorWidth : menuWindow.entryHorizontalPadding * 2 + leadingWidth + Math.min(menuWindow.maxTextWidth, title.implicitWidth) + trailingWidth
                                    width: menuContent.width
                                    height: modelData.isSeparator ? menuWindow.separatorHeight : menuWindow.entryHeight
                                    radius: 7
                                    color: entryMouse.containsMouse && modelData.enabled && !modelData.isSeparator ? theme.alpha(theme.surface1, 0.85) : "transparent"

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 1
                                        visible: menuEntry.modelData.isSeparator
                                        color: theme.alpha(theme.text, 0.12)
                                    }

                                    Text {
                                        id: checkmark

                                        anchors.left: parent.left
                                        anchors.leftMargin: menuWindow.entryHorizontalPadding
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: menuEntry.hasCheckmark ? "✓" : ""
                                        visible: menuEntry.hasCheckmark && !menuEntry.modelData.isSeparator
                                        color: theme.green
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.menuFontPixelSize
                                    }

                                    IconImage {
                                        id: icon

                                        anchors.left: parent.left
                                        anchors.leftMargin: menuWindow.entryHorizontalPadding + (menuEntry.hasCheckmark ? checkmark.implicitWidth + menuWindow.entrySpacing : 0)
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: menuWindow.iconSize
                                        height: menuWindow.iconSize
                                        source: menuEntry.modelData.icon
                                        visible: menuEntry.hasIcon && !menuEntry.modelData.isSeparator
                                    }

                                    Text {
                                        id: title

                                        anchors.left: parent.left
                                        anchors.leftMargin: menuWindow.entryHorizontalPadding + menuEntry.leadingWidth
                                        anchors.right: parent.right
                                        anchors.rightMargin: menuWindow.entryHorizontalPadding + menuEntry.trailingWidth
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: menuEntry.modelData.text
                                        visible: !menuEntry.modelData.isSeparator
                                        color: menuEntry.modelData.enabled ? theme.text : theme.overlay1
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.menuFontPixelSize
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        id: arrow

                                        anchors.right: parent.right
                                        anchors.rightMargin: menuWindow.entryHorizontalPadding
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: menuEntry.modelData.hasChildren ? "›" : ""
                                        visible: menuEntry.modelData.hasChildren && !menuEntry.modelData.isSeparator
                                        color: theme.subtext0
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.barFontPixelSize
                                    }

                                    MouseArea {
                                        id: entryMouse

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: menuEntry.modelData.enabled && !menuEntry.modelData.isSeparator
                                        onClicked: {
                                            if (menuEntry.modelData.hasChildren) {
                                                const position = menuEntry.mapToItem(null, menuEntry.width, 0);
                                                menuEntry.modelData.display(root.barWindow, position.x, position.y);
                                            } else {
                                                trayItem.menuOpen = false;
                                                menuEntry.modelData.triggered();
                                            }
                                        }
                                    }

                                }

                            }

                        }

                    }

                    QsMenuOpener {
                        id: menuOpener

                        menu: trayItem.modelData.menu
                    }

                    Theme {
                        id: theme
                    }

                }

            }

        }

    }

}
