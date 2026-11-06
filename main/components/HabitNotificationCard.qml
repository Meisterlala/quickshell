pragma ComponentBehavior: Bound

import ".."
import QtQuick

Rectangle {
    id: root
    required property var notification

    implicitHeight: content.implicitHeight + 18
    height: implicitHeight
    radius: 12
    color: theme.alpha(theme.red, 0.2)
    border.color: theme.alpha(theme.red, 0.52)
    border.width: 1

    Theme {
        id: theme
    }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 12
        spacing: 4

        Text {
            width: parent.width
            color: theme.text
            elide: Text.ElideRight
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize + 1
            font.bold: true
            text: String(root.notification.title || "Notification")
            textFormat: Text.PlainText
        }

        Text {
            visible: text.length > 0
            width: parent.width
            color: theme.subtext0
            font.family: theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.Wrap
            text: String(root.notification.description || "")
            textFormat: Text.PlainText
        }

        Rectangle {
            visible: Number(root.notification.progress_max || 0) > 0
            width: parent.width
            height: 6
            radius: 3
            color: theme.alpha(theme.text, 0.12)

            Rectangle {
                height: parent.height
                radius: parent.radius
                width: Math.min(parent.width, parent.width * Number(root.notification.progress_current || 0) / Math.max(1, Number(root.notification.progress_max || 1)))
                color: theme.red
            }
        }

        Text {
            visible: text.length > 0
            color: theme.overlay1
            font.family: theme.fontFamily
            font.pixelSize: 10
            text: String(root.notification.progress_label || "")
            textFormat: Text.PlainText
        }
    }
}
