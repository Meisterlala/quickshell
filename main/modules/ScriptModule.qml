import "../components"
import QtQuick
import Quickshell.Io

ModulePill {
    id: root

    required property string moduleName
    property var ipc: null
    property string command: ""
    property int interval: 30000
    property bool parseJson: true
    property bool hideEmptyText: true
    property bool moduleVisible: true
    property string onClickCommand: ""
    property string onRightClickCommand: ""
    property string textOverride: ""
    property string format: "{}"
    property string icon: ""
    property var formatIcons: ({})
    property string currentText: textOverride
    property string currentTooltip: ""
    property string currentClass: ""

    function classList(value) {
        if (Array.isArray(value))
            return value.map(item => String(item));

        if (value === undefined || value === null || String(value).length === 0)
            return [];

        return [String(value)];
    }

    function decodeEntities(value) {
        return value.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&apos;/g, "'");
    }

    function plainTooltip(value) {
        return decodeEntities(String(value ?? "").replace(/\r/g, "\n").replace(/<[^>]*>/g, "").trim());
    }

    function iconFor(parsed, classes) {
        if (icon.length > 0)
            return icon;

        const candidates = [];
        if (parsed.alt !== undefined && parsed.alt !== null)
            candidates.push(String(parsed.alt));

        for (const name of classes)
            candidates.push(name);

        for (const name of candidates) {
            if (formatIcons && formatIcons[name] !== undefined)
                return String(formatIcons[name]);
        }

        return "";
    }

    function applyFormat(value, moduleIcon) {
        return format.replace(/\{\}/g, value).replace(/\{icon\}/g, moduleIcon);
    }

    function runCommand(commandText) {
        if (commandText.length === 0)
            return ;

        actionRunner.exec(["sh", "-lc", commandText]);
    }

    function refresh() {
        if (!moduleVisible)
            return ;

        if (textOverride.length > 0) {
            currentText = textOverride;
            return ;
        }
        refreshRunner.exec(["sh", "-lc", command]);
    }

    function applyOutput(output) {
        const trimmed = output.trim();
        if (trimmed.length === 0) {
            currentText = "";
            currentTooltip = "";
            currentClass = "";
            return ;
        }
        if (!parseJson) {
            currentText = applyFormat(trimmed, icon);
            currentTooltip = "";
            currentClass = "";
            return ;
        }
        try {
            const lines = trimmed.split("\n").filter(line => line.trim().length > 0);
            const parsed = JSON.parse(lines[lines.length - 1]);
            const classes = classList(parsed.class);
            const rawText = String(parsed.text ?? "");
            if (rawText.length === 0 && hideEmptyText)
                currentText = "";
            else
                currentText = applyFormat(rawText, iconFor(parsed, classes)).trim();
            currentTooltip = plainTooltip(parsed.tooltip ?? "");
            currentClass = classes[0] ?? "";
        } catch (error) {
            currentText = applyFormat(trimmed, icon);
            currentTooltip = "";
            currentClass = "error";
        }
    }

    text: currentText
    tooltipText: currentTooltip
    moduleClass: currentClass
    visible: moduleVisible && (!hideEmptyText || currentText.length > 0)
    onClicked: (button) => {
        if (button === Qt.LeftButton)
            runCommand(onClickCommand);

        if (button === Qt.RightButton)
            runCommand(onRightClickCommand || `qs ipc -c main call bar refreshModule ${moduleName}`);

    }
    Component.onCompleted: refresh()
    onModuleVisibleChanged: {
        if (moduleVisible)
            refresh();
        else if (hideEmptyText)
            currentText = "";

    }

    Timer {
        interval: root.interval
        running: root.moduleVisible && root.command.length > 0 && root.interval > 0
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: refreshRunner

        stdout: StdioCollector {
            onStreamFinished: root.applyOutput(this.text)
        }

    }

    Process {
        id: actionRunner
    }

    Connections {
        function onRefreshRequested(name) {
            if (name === root.moduleName || name === "all")
                root.refresh();

        }

        target: root.ipc
    }

}
