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

                anchor.window: root.barWindow
                anchor.rect.x: Math.max(8, Math.min(root.barWindow.width - width - 8, trayItem.mapToItem(null, 0, 0).x))
                anchor.rect.y: root.barWindow.height + 8
                implicitWidth: Math.max(180, Math.min(root.barWindow.width - 16, menuContent.implicitWidth + 16))
                implicitHeight: menuContent.implicitHeight + 16
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

                        anchors.fill: parent
                        anchors.margins: 8

                        Repeater {
                            model: menuOpener.children

                            Rectangle {
                                id: menuEntry

                                required property var modelData

                                implicitWidth: modelData.isSeparator ? 164 : 36 + checkmark.implicitWidth + (icon.visible ? icon.width + entryContent.spacing : 0) + title.implicitWidth + arrow.implicitWidth
                                width: menuContent.width
                                height: modelData.isSeparator ? 9 : 30
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

                                Row {
                                    id: entryContent

                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 8
                                    visible: !menuEntry.modelData.isSeparator

                                    Text {
                                        id: checkmark

                                        anchors.verticalCenter: parent.verticalCenter
                                        text: menuEntry.modelData.checkState === Qt.Checked ? "✓" : ""
                                        visible: text.length > 0
                                        color: theme.green
                                        font.family: "FiraCode Nerd Font"
                                        font.pixelSize: 13
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    IconImage {
                                        id: icon

                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 16
                                        height: 16
                                        source: menuEntry.modelData.icon
                                        visible: menuEntry.modelData.icon.length > 0
                                    }

                                    Text {
                                        id: title

                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(root.barWindow.width * 0.9, implicitWidth)
                                        text: menuEntry.modelData.text
                                        color: menuEntry.modelData.enabled ? theme.text : theme.overlay1
                                        font.family: "FiraCode Nerd Font"
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        id: arrow

                                        anchors.verticalCenter: parent.verticalCenter
                                        text: menuEntry.modelData.hasChildren ? "›" : ""
                                        color: theme.subtext0
                                        font.family: "FiraCode Nerd Font"
                                        font.pixelSize: 14
                                    }

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
