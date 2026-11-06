import ".."
import "ModuleData.js" as ModuleData
import QtQuick
import Quickshell.Widgets

// A labeled percentage bar, optionally split into leading/primary/secondary use.
Item {
    id: root

    required property string label
    required property real percent
    required property string valueText
    required property string accent
    required property string fillColor
    property real leadingPercent: 0
    property string leadingFillColor: fillColor
    property real secondaryPercent: 0
    property string secondaryFillColor: fillColor
    readonly property real boundedPercent: ModuleData.clampPercent(percent)
    readonly property real boundedSecondaryPercent: Math.min(boundedPercent, ModuleData.clampPercent(secondaryPercent))
    readonly property real boundedLeadingPercent: Math.min(boundedPercent - boundedSecondaryPercent, ModuleData.clampPercent(leadingPercent))
    readonly property real primaryPercent: boundedPercent - boundedLeadingPercent - boundedSecondaryPercent

    height: 24

    Theme {
        id: theme
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: 5
        color: theme.alpha(theme.crust, 0.3)
        border.color: theme.alpha(String(root.accent), 0.22)
        border.width: 1
        contentUnderBorder: true

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: root.boundedLeadingPercent > 0
            width: parent.width * root.boundedLeadingPercent / 100
            color: root.leadingFillColor
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: root.primaryPercent > 0
            x: parent.width * root.boundedLeadingPercent / 100
            width: parent.width * root.primaryPercent / 100
            color: root.fillColor
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: root.boundedSecondaryPercent > 0
            x: parent.width * (root.boundedLeadingPercent + root.primaryPercent) / 100
            width: parent.width * root.boundedSecondaryPercent / 100
            color: root.secondaryFillColor
        }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 7
        anchors.rightMargin: 7

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 52
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: 11
            text: root.label
            textFormat: Text.PlainText
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 52
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
            text: root.valueText
            textFormat: Text.PlainText
        }
    }
}
