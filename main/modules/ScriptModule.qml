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
    property string currentText: textOverride
    property string currentClass: ""

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
            currentClass = "";
            return ;
        }
        if (!parseJson) {
            currentText = trimmed;
            currentClass = "";
            return ;
        }
        try {
            const lines = trimmed.split("\n").filter(line => line.trim().length > 0);
            const parsed = JSON.parse(lines[lines.length - 1]);
            currentText = String(parsed.text ?? "");
            currentClass = Array.isArray(parsed.class) ? parsed.class[0] ?? "" : String(parsed.class ?? "");
        } catch (error) {
            currentText = trimmed;
            currentClass = "error";
        }
    }

    text: currentText
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
