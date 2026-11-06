pragma ComponentBehavior: Bound

import ".."
import QtQuick
import Quickshell
import "../services/NotificationLogic.js" as Logic

PopupSurface {
    id: root
    required property var entry
    required property var service
    property bool compact: false
    readonly property bool hovered: hover.hovered
    property real swipeOffset: 0
    property bool dismissing: false
    readonly property bool interacting: hovered || replyInput.activeFocus || swipe.active || dismissing
    readonly property string iconSource: {
        const icon = String(entry.icon || "");
        return Logic.safeImage(icon) || (!icon.includes(":") && !icon.includes("/") ? Quickshell.iconPath(icon, true) : "");
    }
    readonly property string imageSource: Logic.safeImage(entry.image)
    onImageSourceChanged: {
        if (sideIcon)
            sideIcon.fallbackToIcon = false;
    }
    implicitHeight: Math.max(content.implicitHeight, sideIcon.visible ? sideIcon.height : 0) + 24
    color: theme.alpha(theme.base, 0.97)
    border.color: entry.urgency === 2 ? theme.red : entry.unread ? theme.alpha(theme.sky, 0.5) : theme.alpha(theme.text, 0.12)

    transform: Translate {
        x: root.swipeOffset
    }
    opacity: 1 - Math.min(Math.abs(swipeOffset) / Math.max(1, width), 1)

    Theme {
        id: theme
    }
    HoverHandler {
        id: hover
    }
    DragHandler {
        id: swipe
        target: null
        acceptedButtons: Qt.LeftButton
        yAxis.enabled: false
        onTranslationChanged: delta => {
            if (active)
                root.swipeOffset += delta.x;
        }
        onActiveChanged: {
            if (active) {
                settle.stop();
            } else {
                root.dismissing = Math.abs(root.swipeOffset) >= Math.min(100, root.width * 0.25);
                settle.to = root.dismissing ? (root.swipeOffset < 0 ? -root.width : root.width) : 0;
                settle.restart();
            }
        }
    }
    NumberAnimation {
        id: settle
        target: root
        property: "swipeOffset"
        duration: 160
        easing.type: Easing.OutCubic
        onFinished: {
            if (root.dismissing)
                root.service.dismiss(root.entry.uid);
        }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button !== Qt.LeftButton)
                root.service.dismiss(root.entry.uid);
            else
                root.service.invoke(root.entry.uid, "default");
        }
    }

    Image {
        id: sideIcon
        property bool fallbackToIcon: false
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        height: 48
        source: !fallbackToIcon && root.imageSource ? root.imageSource : root.iconSource
        sourceSize: Qt.size(96, 96)
        fillMode: Image.PreserveAspectFit
        visible: status === Image.Ready
        asynchronous: true
        onStatusChanged: {
            if (status === Image.Error)
                fallbackToIcon = true;
        }
    }

    Column {
        id: content
        x: 12
        y: 12
        width: parent.width - 24 - (sideIcon.visible ? sideIcon.width + 12 : 0)
        spacing: 8

        Text {
            width: parent.width
            height: 22
            verticalAlignment: Text.AlignVCenter
            text: root.entry.app
            textFormat: Text.PlainText
            color: theme.subtext0
            elide: Text.ElideRight
            font.family: theme.fontFamily
            font.pixelSize: 11
        }
        Text {
            width: parent.width
            text: root.entry.summary
            textFormat: Text.PlainText
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: 14
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: root.compact ? 3 : 8
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: text.length > 0
            text: root.entry.body
            textFormat: Text.PlainText
            color: theme.subtext0
            font.family: theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.Wrap
            maximumLineCount: root.compact ? 5 : 30
            elide: Text.ElideRight
        }
        Flow {
            width: parent.width
            spacing: 6
            visible: root.entry.live && children.length > 0
            Repeater {
                model: root.entry.actions.filter(action => action.id !== "default" && action.id !== "inline-reply")
                NotificationButton {
                    required property var modelData
                    text: modelData.text
                    onClicked: root.service.invoke(root.entry.uid, modelData.id)
                }
            }
        }
        NotificationButton {
            visible: root.compact && root.entry.live && root.entry.inlineReply
            text: "Reply…"
            onClicked: root.service.toggleCenter(root.entry.screen)
        }
        Rectangle {
            width: parent.width
            height: 34
            visible: !root.compact && root.entry.live && root.entry.inlineReply
            color: theme.surface0
            radius: 8
            TextInput {
                id: replyInput
                anchors.left: parent.left
                anchors.right: sendButton.left
                anchors.margins: 8
                anchors.verticalCenter: parent.verticalCenter
                color: theme.text
                font.pixelSize: 12
                selectByMouse: true
                clip: true
                onAccepted: sendButton.clicked()
                Text {
                    anchors.fill: parent
                    visible: !replyInput.text && !replyInput.activeFocus
                    text: root.entry.replyPlaceholder
                    textFormat: Text.PlainText
                    color: theme.overlay1
                    font.pixelSize: 12
                }
            }
            NotificationButton {
                id: sendButton
                anchors.right: parent.right
                text: "Send"
                onClicked: {
                    if (root.service.reply(root.entry.uid, replyInput.text))
                        replyInput.text = "";
                }
            }
        }
        Text {
            visible: !root.compact
            text: Qt.formatDateTime(new Date(root.entry.timestamp), "ddd, dd MMM · hh:mm")
            color: theme.overlay1
            font.family: theme.fontFamily
            font.pixelSize: 10
        }
    }
}
