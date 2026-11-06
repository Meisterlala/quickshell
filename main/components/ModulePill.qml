pragma ComponentBehavior: Bound

import ".."
import QtQuick

Rectangle {
    id: root

    property alias text: label.text
    property string moduleClass: ""
    property string tooltipText: ""
    property var tooltipEntries: []
    property var barWindow: null
    property bool hoverable: true
    property bool backgroundVisible: true
    property int fontPixelSize: theme.barFontPixelSize
    property int horizontalPadding: 20
    property int minimumWidth: 30
    readonly property bool hovered: mouse.containsMouse
    readonly property bool tooltipVisible: root.tooltipText.length > 0 && mouse.containsMouse

    signal clicked(int button)

    implicitWidth: Math.max(minimumWidth, label.implicitWidth + horizontalPadding)
    implicitHeight: 34
    radius: 8
    color: backgroundVisible ? (mouse.containsMouse && hoverable ? theme.surface2 : theme.alpha(theme.surface0, 0.28)) : "transparent"
    border.color: backgroundVisible ? theme.alpha(theme.text, 0.1) : "transparent"
    border.width: backgroundVisible ? 1 : 0
    visible: text.length > 0

    Theme {
        id: theme
    }

    Text {
        id: label

        anchors.centerIn: parent
        color: theme.classColor(root.moduleClass)
        font.family: theme.fontFamily
        font.pixelSize: root.fontPixelSize
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignVCenter

        SequentialAnimation on opacity {
            running: root.visible && Qt.colorEqual(label.color, theme.red)
            loops: Animation.Infinite
            onRunningChanged: {
                if (!running)
                    label.opacity = 1;
            }

            NumberAnimation {
                to: 0.4
                duration: 500
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                to: 1
                duration: 500
                easing.type: Easing.InOutSine
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        onClicked: mouse => root.clicked(mouse.button)
    }

    BarPopup {
        id: tooltipWindow

        readonly property int maxTooltipWidth: root.barWindow ? Math.min(560, Math.max(240, root.barWindow.width - margin * 2)) : 360
        readonly property int maxTooltipHeight: root.barWindow && root.barWindow.screen ? Math.max(120, Math.round((root.barWindow.screen.height - root.barWindow.height - margin * 2) * 0.75)) : 480

        barWindow: root.barWindow
        anchorItem: root
        shown: root.tooltipVisible
        readonly property bool structured: root.tooltipEntries.length > 0
        readonly property int padding: structured ? 16 : 10

        implicitWidth: Math.min(maxTooltipWidth, structured ? 380 : tooltipLabel.implicitWidth + 28)
        implicitHeight: Math.min(maxTooltipHeight, tooltipContent.implicitHeight + padding * 2)

        PopupSurface {
            anchors.fill: parent
            clip: true

            Flickable {
                anchors.fill: parent
                anchors.margins: tooltipWindow.padding
                contentWidth: width
                contentHeight: tooltipContent.implicitHeight
                clip: true

                Column {
                    id: tooltipContent

                    width: parent.width
                    spacing: 14

                    Text {
                        id: tooltipLabel

                        visible: !tooltipWindow.structured
                        text: root.tooltipText
                        color: theme.text
                        font.family: theme.fontFamily
                        font.pixelSize: theme.tooltipFontPixelSize
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        width: parent.width
                    }

                    Repeater {
                        model: root.tooltipEntries

                        Column {
                            required property var modelData

                            width: tooltipContent.width
                            spacing: 5

                            Text {
                                width: parent.width
                                text: parent.modelData.title
                                color: theme.text
                                font.family: theme.fontFamily
                                font.pixelSize: theme.tooltipFontPixelSize
                                font.bold: true
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                            }

                            Text {
                                width: parent.width
                                visible: text.length > 0
                                text: parent.modelData.body
                                color: theme.subtext0
                                font.family: theme.fontFamily
                                font.pixelSize: theme.tooltipFontPixelSize
                                lineHeight: 1.25
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }
}
