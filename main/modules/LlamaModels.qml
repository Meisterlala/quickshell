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
    property int interval: 5000
    property int activeInterval: 1000
    property int rateWindowMs: 3000
    property string command: "/home/misti/.config/quickshell/main/scripts/llama_models.py"
    property var models: []
    property var generationSamples: ({})
    readonly property int activeCount: models.filter(model => model.active).length
    readonly property real tokensPerSecond: models.reduce((total, model) => total + (model.active && model.ratePhase === "generation" ? Number(model.tokensPerSecond || 0) : 0), 0)
    readonly property bool generating: models.some(model => model.active && model.ratePhase === "generation")
    readonly property bool prompting: models.some(model => model.active && model.ratePhase === "prompt")

    function refresh() {
        if (!moduleVisible || refreshRunner.running)
            return;

        refreshRunner.exec(["/usr/bin/python3", command]);
    }

    function applyOutput(output) {
        if (!moduleVisible)
            return;

        const trimmed = output.trim();
        if (trimmed.length === 0) {
            models = [];
            generationSamples = ({});
            return;
        }

        try {
            const lines = trimmed.split("\n").filter(line => line.trim().length > 0);
            const parsed = JSON.parse(lines[lines.length - 1]);
            const now = Date.now();
            const nextModels = Array.isArray(parsed.models) ? parsed.models : [];
            for (const model of nextModels)
                updateRate(model, now);
            for (const id of Object.keys(generationSamples)) {
                if (!nextModels.some(model => model.id === id))
                    delete generationSamples[id];
            }
            models = nextModels;
        } catch (error) {
            models = [];
            generationSamples = ({});
        }
    }

    function updateRate(model, now) {
        model.tokensPerSecond = 0;
        model.ratePhase = "";
        if (!model.active || model.generationId.length === 0) {
            delete generationSamples[model.id];
            return;
        }

        let state = generationSamples[model.id];
        if (!state || state.generationId !== model.generationId)
            state = { generationId: model.generationId, samples: [] };

        const sample = {
            timestamp: now,
            generated: Number(model.generationTokens || 0),
            prompt: Number(model.promptTokens || 0)
        };
        let previous = state.samples[state.samples.length - 1];
        if (previous && (sample.generated < previous.generated || sample.prompt < previous.prompt)) {
            state.samples = [];
            previous = null;
        }
        state.samples.push(sample);
        state.samples = state.samples.filter(item => item.timestamp >= now - rateWindowMs);
        generationSamples[model.id] = state;

        const first = state.samples[0];
        const elapsed = sample.timestamp - first.timestamp;
        const promptActive = previous ? sample.prompt > previous.prompt : sample.prompt > 0;
        const tokens = promptActive ? sample.prompt - first.prompt : sample.generated - first.generated;
        model.tokensPerSecond = elapsed > 0 ? Math.max(0, tokens) * 1000 / elapsed : 0;
        model.ratePhase = promptActive ? "prompt" : "generation";
    }

    function rateText(value) {
        return Number(value || 0).toFixed(0);
    }

    function compactStatusText() {
        if (activeCount === 0)
            return String(models.length);
        if (generating)
            return `${rateText(tokensPerSecond)} t/s`;
        return prompting ? "Prompt" : "0 t/s";
    }

    function summaryStatusText() {
        if (activeCount === 0)
            return "All models idle";
        if (generating)
            return `${activeCount} active · ${rateText(tokensPerSecond)} generated tokens/s`;
        return prompting ? `${activeCount} active · Processing prompt` : `${activeCount} active · 0 generated tokens/s`;
    }

    function modelStatusText(model) {
        if (model.status === "loading")
            return "Loading";
        if (!model.active)
            return "Idle";
        return model.ratePhase === "prompt" ? "Prompt" : `${rateText(model.tokensPerSecond)} t/s`;
    }

    function compactName(value) {
        return String(value || "Unknown model").replace(/^.*\//, "").replace(/-GGUF.*$/i, "");
    }

    function paramsText(value) {
        const params = Number(value || 0);
        return params > 0 ? `${(params / 1000000000).toFixed(1)}B params` : "";
    }

    function sizeText(value) {
        const size = Number(value || 0);
        return size > 0 ? `${(size / 1073741824).toFixed(1)} GiB` : "";
    }

    function modelDetails(model) {
        const details = [];
        const params = paramsText(model.params);
        const size = sizeText(model.size);
        if (params.length > 0)
            details.push(params);
        if (size.length > 0)
            details.push(size);
        if (Number(model.contextSize || 0) > 0)
            details.push(`${Number(model.contextSize).toLocaleString()} ctx`);
        if (Array.isArray(model.modalities) && model.modalities.length > 0)
            details.push(model.modalities.join(" + "));
        return details.join(" · ");
    }

    implicitWidth: compactContent.implicitWidth + 20
    implicitHeight: 34
    radius: 8
    color: activeCount > 0 ? theme.alpha(theme.green, 0.38) : mouse.containsMouse ? theme.surface2 : theme.alpha(theme.surface0, 0.28)
    border.color: activeCount > 0 ? theme.alpha(theme.green, 0.72) : theme.alpha(theme.text, 0.1)
    border.width: 1
    contentUnderBorder: true
    visible: moduleVisible && models.length > 0

    Theme {
        id: theme
    }

    Row {
        id: compactContent

        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: theme.sky
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: "󰧑"
            textFormat: Text.PlainText
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: theme.barFontPixelSize
            text: root.compactStatusText()
            textFormat: Text.PlainText
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        onClicked: root.refresh()
        onContainsMouseChanged: {
            if (containsMouse)
                root.refresh();
        }
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
        implicitWidth: 420
        implicitHeight: detailsColumn.implicitHeight + 28
        color: "transparent"
        visible: root.barWindow && mouse.containsMouse && root.visible

        PopupSurface {
            anchors.fill: parent
            clip: true

            Column {
                id: detailsColumn

                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: theme.sky
                        font.family: theme.fontFamily
                        font.pixelSize: theme.barFontPixelSize + 4
                        text: "󰧑"
                    }

                    Column {
                        width: parent.width - 32
                        spacing: 2

                        Text {
                            width: parent.width
                            color: theme.text
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize + 2
                            font.bold: true
                            text: `${root.models.length} model${root.models.length === 1 ? "" : "s"} loaded`
                        }

                        Text {
                            width: parent.width
                            color: root.activeCount > 0 ? theme.green : theme.subtext0
                            font.family: theme.fontFamily
                            font.pixelSize: theme.tooltipFontPixelSize
                            text: root.summaryStatusText()
                        }
                    }
                }

                Repeater {
                    model: root.models

                    Rectangle {
                        id: modelRow

                        required property var modelData
                        width: detailsColumn.width
                        height: modelInfo.implicitHeight + 16
                        radius: 6
                        color: theme.alpha(theme.crust, 0.3)
                        border.color: theme.alpha(modelData.active ? theme.green : modelData.status === "loading" ? theme.yellow : theme.text, 0.22)
                        border.width: 1

                        Row {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelRow.modelData.active ? theme.green : modelRow.modelData.status === "loading" ? theme.yellow : theme.overlay1
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                text: "●"
                            }

                            Column {
                                id: modelInfo

                                width: parent.width - 20
                                spacing: 2

                                Row {
                                    width: parent.width

                                    Text {
                                        width: parent.width - stateLabel.width
                                        color: theme.text
                                        elide: Text.ElideMiddle
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.tooltipFontPixelSize
                                        font.bold: true
                                        text: root.compactName(modelRow.modelData.id)
                                    }

                                    Text {
                                        id: stateLabel

                                        color: modelRow.modelData.active ? theme.green : modelRow.modelData.status === "loading" ? theme.yellow : theme.subtext0
                                        font.family: theme.fontFamily
                                        font.pixelSize: theme.tooltipFontPixelSize
                                        text: root.modelStatusText(modelRow.modelData)
                                    }
                                }

                                Text {
                                    width: parent.width
                                    visible: text.length > 0
                                    color: theme.subtext0
                                    elide: Text.ElideRight
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.tooltipFontPixelSize - 1
                                    text: root.modelDetails(modelRow.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        interval: root.models.length > 0 ? root.activeInterval : root.interval
        running: root.moduleVisible && interval > 0
        repeat: true
        onTriggered: root.refresh()
        onIntervalChanged: {
            if (running)
                restart();
        }
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
        else {
            refreshRunner.running = false;
            models = [];
            generationSamples = ({});
        }
    }
}
