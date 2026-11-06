import "../components"
import "../components/ModuleData.js" as ModuleData
import QtQuick

ModulePill {
    id: root

    property var ipc: null
    property bool moduleVisible: true

    function refresh() {
        if (moduleVisible && !runner.running)
            runner.run();
    }

    function applyOutput(output) {
        try {
            const data = ModuleData.parseObject(output);
            const count = String(data.text ?? "");
            text = count.length > 0 ? count + " 󰒲" : "";
            moduleClass = String(data.class ?? "");
            tooltipEntries = data.entries || [];
            tooltipText = String(data.tooltip || (tooltipEntries.length > 0 ? "Idle inhibitors" : ""));
        } catch (error) {
            text = "!";
            moduleClass = "error";
            tooltipEntries = [];
            tooltipText = "Invalid idle inhibitor response";
        }
    }

    visible: moduleVisible && text.length > 0
    Component.onCompleted: refresh()
    onModuleVisibleChanged: {
        if (moduleVisible) {
            refresh();
        } else {
            runner.cancel();
            text = "";
        }
    }
    onClicked: refresh()

    Timer {
        interval: 5000
        running: root.moduleVisible
        repeat: true
        onTriggered: root.refresh()
    }

    HelperProcess {
        id: runner

        helper: "idle-inhibitors"
        onOutput: output => {
            return root.applyOutput(output);
        }
        onExited: code => {
            if (code !== 0 && root.moduleVisible) {
                root.text = "!";
                root.moduleClass = "error";
                root.tooltipEntries = [];
                root.tooltipText = "Could not read idle inhibitors";
            }
        }
    }

    Connections {
        function onRefreshRequested(name) {
            if (name === "hypridle" || name === "all")
                root.refresh();
        }

        target: root.ipc
    }
}
