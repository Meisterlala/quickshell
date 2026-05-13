import "../components"
import ".."
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Row {
    id: root

    required property var barWindow

    spacing: 8

    Repeater {
        model: SystemTray.items

        Item {
            id: trayItem

            required property var modelData
            property bool menuOpen: false

            function displayMenu() {
                if (!modelData.hasMenu)
                    return;

                menuOpen = !menuOpen;
            }

            width: 24
            height: 30

            IconImage {
                anchors.centerIn: parent
                width: 20
                height: 20
                source: modelData.icon
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
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
                visible: trayItem.menuOpen
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
                                    font.family: "FiraCode Nerd Font"
                                    font.pixelSize: 13
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
                                    font.family: "FiraCode Nerd Font"
                                    font.pixelSize: 13
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
                                    font.family: "FiraCode Nerd Font"
                                    font.pixelSize: 14
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
