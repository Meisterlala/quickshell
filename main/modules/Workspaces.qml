import "../components"
import QtQuick
import Quickshell.Hyprland

Row {
    id: root

    required property var barWindow

    function monitorMatches(workspace) {
        if (!workspace || !workspace.monitor || !barWindow.screen)
            return true;

        return workspace.monitor.name === barWindow.screen.name;
    }

    function workspaceText(workspace) {
        if (!workspace)
            return "";

        const count = workspace.toplevels ? workspace.toplevels.values.length : 0;
        if (count === 0)
            return String(workspace.id);

        return `${workspace.id} ${count}`;
    }

    spacing: 4

    Repeater {
        model: Hyprland.workspaces

        ModulePill {
            required property var modelData

            text: root.workspaceText(modelData)
            moduleClass: modelData.urgent ? "critical" : ""
            visible: root.monitorMatches(modelData)
            color: modelData.active ? "#585b70" : (modelData.toplevels && modelData.toplevels.values.length > 0 ? "#55313244" : "#22313244")
            onClicked: modelData.activate()
        }

    }

}
