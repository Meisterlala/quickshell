import ".."
import QtQuick

Item {
    id: root

    property var values: []
    property int maxSamples: 48
    property real warningThreshold: 70
    property real criticalThreshold: 90
    property int barRadius: 0
    property color lowColor: theme.green
    property color warningColor: theme.yellow
    property color criticalColor: theme.red
    property color backgroundColor: theme.alpha(theme.crust, 0.28)
    property color borderColor: theme.alpha(theme.text, 0.1)

    function clampPercent(value) {
        return Math.max(0, Math.min(100, Number(value || 0)));
    }

    function barColor(value) {
        if (value >= criticalThreshold)
            return criticalColor;

        if (value >= warningThreshold)
            return warningColor;

        return lowColor;
    }

    function valueAt(slot) {
        const offset = maxSamples - sampleCount;
        const index = Number(slot) - offset;
        if (index < 0 || index >= sampleCount)
            return -1;

        return clampPercent(visibleValues[index]);
    }

    readonly property int sampleCount: Math.min(maxSamples, values.length)
    readonly property var visibleValues: values.slice(Math.max(0, values.length - sampleCount))
    implicitHeight: 46

    Theme {
        id: theme
    }

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: root.backgroundColor
        border.color: root.borderColor
        border.width: 1
    }

    Item {
        id: chart

        anchors.fill: parent
        anchors.margins: 1
        clip: true

        Repeater {
            model: root.maxSamples

            Item {
                required property int modelData

                readonly property real value: root.valueAt(modelData)
                readonly property real slotWidth: root.maxSamples > 0 ? chart.width / root.maxSamples : chart.width

                width: slotWidth
                height: parent.height
                x: modelData * slotWidth

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: parent.value >= 0
                    height: parent.height * parent.value / 100
                    radius: root.barRadius
                    color: root.barColor(parent.value)
                    opacity: 0.86
                }
            }
        }
    }
}
