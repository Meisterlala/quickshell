import "../components"
import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

ClippingRectangle {
    id: root

    required property var barWindow
    property bool moduleVisible: true
    property int interval: 300000
    property string command: "/home/misti/.config/quickshell/main/scripts/codex_usage.py"
    readonly property int compactHorizontalPadding: 20
    readonly property int compactHeight: 34
    readonly property int cornerRadius: 8
    property var primary: ({
        "label": "5h",
        "usedPercent": 0,
        "resetIn": "",
        "resetAt": ""
    })
    property var secondary: ({
        "label": "7d",
        "usedPercent": 0,
        "resetIn": "",
        "resetAt": ""
    })
    property var credits: ({
        "hasCredits": false,
        "unlimited": false,
        "balance": null
    })
    property string state: "normal"
    property string errorText: ""
    readonly property bool hasData: errorText.length === 0
    readonly property real primaryPercent: clampPercent(primary.usedPercent)
    readonly property real secondaryPercent: clampPercent(secondary.usedPercent)
    readonly property bool hasCredits: Boolean(credits.hasCredits || credits.unlimited || (credits.balance && String(credits.balance) !== "0"))
    readonly property string accent: state === "critical" || errorText.length > 0 ? theme.red : state === "warning" ? theme.yellow : theme.sky
    readonly property string accentSoft: theme.alpha(String(accent), state === "normal" ? 0.3 : 0.42)
    readonly property bool tooltipVisible: mouse.containsMouse
    readonly property string creditsText: credits.unlimited ? "credits: unlimited" : `credits balance: ${credits.balance ?? "n/a"}`

    function clampPercent(value) {
        return Math.max(0, Math.min(100, Number(value || 0)));
    }

    function plainTooltip(value) {
        return String(value ?? "").replace(/\r/g, "\n").replace(/<[^>]*>/g, "").trim();
    }

    function resetText(windowData) {
        return `resets in ${windowData.resetIn || "?"} at ${windowData.resetAt || "?"}`;
    }

    function refresh() {
        if (!moduleVisible)
            return;

        refreshRunner.exec(["/usr/sbin/python3", command]);
    }

    function applyOutput(output) {
        const trimmed = output.trim();
        if (trimmed.length === 0) {
            errorText = "No Codex usage output";
            return;
        }

        try {
            const lines = trimmed.split("\n").filter(line => line.trim().length > 0);
            const parsed = JSON.parse(lines[lines.length - 1]);
            if (parsed.error) {
                errorText = plainTooltip(parsed.error);
                return;
            }

            primary = parsed.primary || primary;
            secondary = parsed.secondary || secondary;
            credits = parsed.credits || credits;
            state = String(parsed.state || "normal");
            errorText = "";
        } catch (error) {
            errorText = plainTooltip(trimmed);
        }
    }

    implicitWidth: errorText.length > 0 ? errorLabel.implicitWidth + 24 : compactContent.implicitWidth + compactHorizontalPadding
    implicitHeight: compactHeight
    radius: cornerRadius
    color: mouse.containsMouse ? theme.surface2 : theme.alpha(theme.surface0, 0.28)
    border.color: theme.alpha(theme.text, 0.1)
    border.width: 1
    contentUnderBorder: true
    visible: moduleVisible

    Theme {
        id: theme
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: root.hasData
        width: parent.width * root.secondaryPercent / 100
        radius: 0
        color: root.accentSoft
    }

    Row {
        id: compactContent

        anchors.centerIn: parent
        visible: root.hasData
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: root.accent
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: "󱙺"
        }

        Text {
            id: usageLabel

            anchors.verticalCenter: parent.verticalCenter
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            font.bold: false
            text: `${Math.round(root.primaryPercent)}%`
        }
    }

    Text {
        id: errorLabel

        anchors.centerIn: parent
        visible: !root.hasData
        color: theme.red
        font.family: theme.fontFamily
        font.pixelSize: theme.barFontPixelSize
        text: "Codex: err"
    }

    PopupWindow {
        id: tooltipWindow

        readonly property int margin: 8

        anchor.window: root.barWindow
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeY
        anchor.rect.x: root.barWindow ? Math.max(margin, Math.min(root.barWindow.width - width - margin, root.mapToItem(null, 0, 0).x + root.width / 2 - width / 2)) : 0
        anchor.rect.y: root.barWindow ? root.barWindow.height + margin : root.height + margin
        anchor.rect.width: root.width
        anchor.rect.height: root.height
        implicitWidth: 300
        implicitHeight: root.errorText.length > 0 ? errorPopupLabel.implicitHeight + 24 : detailsColumn.implicitHeight + 28
        color: "transparent"
        visible: root.barWindow && root.tooltipVisible

        PopupSurface {
            anchors.fill: parent

            Text {
                id: errorPopupLabel

                anchors.fill: parent
                anchors.margins: 12
                visible: root.errorText.length > 0
                text: root.errorText
                color: theme.red
                font.family: theme.fontFamily
                font.pixelSize: theme.tooltipFontPixelSize
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }

            Column {
                id: detailsColumn

                anchors.fill: parent
                anchors.margins: 14
                visible: root.errorText.length === 0
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        color: root.accent
                        font.family: theme.fontFamily
                        font.pixelSize: theme.barFontPixelSize + 2
                        text: "󱙺"
                    }

                    Text {
                        width: parent.width - 28
                        color: theme.text
                        font.family: theme.fontFamily
                        font.pixelSize: theme.tooltipFontPixelSize + 1
                        font.bold: true
                        text: "Codex usage"
                    }

                }

                UsageDetail {
                    width: parent.width
                    usage: root.primary
                    percent: root.primaryPercent
                    accent: root.accent
                    fillColor: root.accentSoft
                }

                UsageDetail {
                    width: parent.width
                    usage: root.secondary
                    percent: root.secondaryPercent
                    accent: root.accent
                    fillColor: root.accentSoft
                }

                Rectangle {
                    visible: root.hasCredits
                    width: parent.width
                    height: 1
                    color: theme.alpha(theme.text, 0.1)
                }

                Text {
                    visible: root.hasCredits
                    width: parent.width
                    color: theme.subtext0
                    font.family: theme.fontFamily
                    font.pixelSize: theme.tooltipFontPixelSize
                    text: root.creditsText
                }
            }

        }

    }

    component UsageDetail: Column {
        id: detailRoot

        required property var usage
        required property real percent
        required property string accent
        required property string fillColor

        spacing: 3

        UsageBar {
            width: parent.width
            label: String(detailRoot.usage.label || "")
            percent: detailRoot.percent
            accent: detailRoot.accent
            fillColor: detailRoot.fillColor
        }

        Text {
            width: parent.width
            color: theme.subtext0
            font.family: theme.fontFamily
            font.pixelSize: theme.tooltipFontPixelSize
            text: root.resetText(detailRoot.usage)
        }
    }

    component UsageBar: Item {
        id: rowRoot

        required property string label
        required property real percent
        required property string accent
        required property string fillColor
        property int barHeight: 22
        property int fontPixelSize: 11
        property int labelWidth: 34

        height: barHeight

        ClippingRectangle {
            anchors.fill: parent
            radius: 4
            color: theme.alpha(theme.crust, 0.28)
            border.color: theme.alpha(String(rowRoot.accent), 0.22)
            border.width: 1
            contentUnderBorder: true

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(3, parent.width * rowRoot.percent / 100)
                radius: 0
                color: rowRoot.fillColor
            }
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 5
            anchors.rightMargin: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: rowRoot.labelWidth
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: rowRoot.fontPixelSize
                text: rowRoot.label
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - rowRoot.labelWidth
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: rowRoot.fontPixelSize
                horizontalAlignment: Text.AlignRight
                text: `${Math.round(rowRoot.percent)}%`
            }

        }

    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        z: 10
        onClicked: root.refresh()
    }

    Timer {
        interval: root.interval
        running: root.moduleVisible && root.interval > 0
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: refreshRunner

        stdout: StdioCollector {
            onStreamFinished: root.applyOutput(this.text)
        }

    }

    Component.onCompleted: refresh()
    onModuleVisibleChanged: {
        if (moduleVisible)
            refresh();

    }
}
