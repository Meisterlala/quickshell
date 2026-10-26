import ".."
import QtQuick

Rectangle {
    id: root
    property string text: ""
    property string icon: ""
    property bool checked: false
    signal clicked()

    implicitWidth: content.implicitWidth + 20
    implicitHeight: 34
    radius: 8
    color: checked ? theme.alpha(theme.sky, mouse.pressed ? 0.2 : 0.12)
        : theme.alpha(theme.text, mouse.pressed ? 0.12 : mouse.containsMouse ? 0.08 : 0.035)
    opacity: enabled ? 1 : 0.35
    border.width: 1
    border.color: checked ? theme.alpha(theme.sky, 0.35) : theme.alpha(theme.text, mouse.containsMouse ? 0.16 : 0.07)

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    Theme { id: theme }
    Row {
        id: content
        anchors.centerIn: parent
        spacing: root.icon && root.text ? 7 : 0
        Text {
            visible: root.icon.length > 0
            text: root.icon
            textFormat: Text.PlainText
            color: root.checked ? theme.sky : theme.subtext0
            font.family: theme.fontFamily
            font.pixelSize: 16
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: root.text.length > 0
            text: root.text
            textFormat: Text.PlainText
            color: root.checked ? theme.sky : theme.text
            font.family: theme.fontFamily
            font.pixelSize: 12
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
