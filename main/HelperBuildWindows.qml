pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property var service

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window
            required property var modelData
            screen: modelData
            visible: root.service.visible
            color: "transparent"
            implicitWidth: Math.min(560, modelData.width - 32)
            implicitHeight: content.implicitHeight + 32
            anchors {
                top: true
            }
            margins {
                top: 54
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell-helper-build"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Theme {
                id: theme
            }

            Rectangle {
                anchors.fill: parent
                radius: 12
                color: theme.base
                border.width: 1
                border.color: root.service.state === "error" ? theme.red : theme.sky
            }

            Column {
                id: content
                x: 16
                y: 16
                width: parent.width - 32
                spacing: 10

                Text {
                    width: parent.width
                    text: root.service.state === "error" ? "Go helper unavailable" : "Compiling Go helper · " + root.service.elapsed
                    color: root.service.state === "error" ? theme.red : theme.sky
                    font.family: theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                    textFormat: Text.PlainText
                }

                Text {
                    visible: root.service.state === "error"
                    width: parent.width
                    text: root.service.message
                    color: theme.text
                    font.family: theme.fontFamily
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }

                Text {
                    width: parent.width
                    text: root.service.buildOutput || (root.service.state === "building" ? root.service.message : "")
                    visible: text.length > 0
                    color: theme.subtext0
                    font.family: "monospace"
                    font.pixelSize: 11
                    maximumLineCount: 10
                    elide: Text.ElideLeft
                    textFormat: Text.PlainText
                }

                Rectangle {
                    visible: root.service.state === "error"
                    implicitWidth: retryLabel.implicitWidth + 24
                    implicitHeight: 30
                    radius: 6
                    color: retryMouse.containsMouse ? theme.surface2 : theme.surface1
                    Text {
                        id: retryLabel
                        anchors.centerIn: parent
                        text: "Retry"
                        color: theme.text
                        font.family: theme.fontFamily
                    }
                    MouseArea {
                        id: retryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root.service.busy
                        onClicked: root.service.retry()
                    }
                }
            }
        }
    }
}
