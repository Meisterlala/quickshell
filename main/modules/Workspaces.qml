import "../components"
import ".."
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

    Theme {
        id: theme
    }

    Repeater {
        model: Hyprland.workspaces

        ModulePill {
            required property var modelData

            barWindow: root.barWindow
            text: root.workspaceText(modelData)
            moduleClass: modelData.urgent ? "critical" : ""
            visible: root.monitorMatches(modelData)
            color: modelData.active ? theme.surface2 : (modelData.toplevels && modelData.toplevels.values.length > 0 ? theme.alpha(theme.surface0, 0.8) : theme.alpha(theme.surface0, 0.2))
            border.color: modelData.toplevels && modelData.toplevels.values.length > 0 ? theme.alpha(theme.text, 0.1) : "transparent"
            onClicked: modelData.activate()
        }

    }

}
