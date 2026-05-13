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

        runner.exec(["sh", "-lc", commandText]);
    }

    function refresh() {
        if (textOverride.length > 0) {
            currentText = textOverride;
            return ;
        }
        runCommand(command);
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
            const parsed = JSON.parse(trimmed);
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

    Timer {
        interval: root.interval
        running: root.command.length > 0 && root.interval > 0
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: runner

        stdout: StdioCollector {
            onStreamFinished: root.applyOutput(this.text)
        }

    }

    Connections {
        function onRefreshRequested(name) {
            if (name === root.moduleName || name === "all")
                root.refresh();

        }

        target: root.ipc
    }

}
