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

    function isSpecialWorkspace(workspace) {
        return workspace && typeof workspace.name === "string" && workspace.name.indexOf("special:") === 0;
    }

    spacing: 4

    Repeater {
        model: Hyprland.workspaces.values.filter(workspace => root.monitorMatches(workspace) && !root.isSpecialWorkspace(workspace))

        WorkspacePill {
            required property var modelData

            barWindow: root.barWindow
            workspace: modelData
            onClicked: modelData.activate()
        }

    }

}
