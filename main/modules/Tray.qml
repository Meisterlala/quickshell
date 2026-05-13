import "../components"
import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Row {
    id: root

    required property var barWindow

    spacing: 8

    Repeater {
        model: SystemTray.items

        Item {
            required property var modelData

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
                        modelData.display(root.barWindow, parent.x, root.barWindow.height);
                }
            }

        }

    }

}
