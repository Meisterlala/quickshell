import ".."
import QtQuick

Rectangle {
    id: root

    property alias text: label.text
    property string moduleClass: ""
    property bool hoverable: true

    signal clicked(int button)

    implicitWidth: Math.max(30, label.implicitWidth + 20)
    implicitHeight: 30
    radius: 8
    color: mouse.containsMouse && hoverable ? theme.surface2 : theme.alpha(theme.surface0, 0.55)
    border.color: theme.alpha(theme.text, 0.1)
    border.width: 1
    visible: text.length > 0

    Theme {
        id: theme
    }

    Text {
        id: label

        anchors.centerIn: parent
        color: theme.classColor(root.moduleClass)
        font.family: "FiraCode Nerd Font"
        font.pixelSize: 14
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        onClicked: root.clicked(mouse.button)
    }

}
