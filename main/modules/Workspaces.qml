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

    spacing: 4

    Repeater {
        model: Hyprland.workspaces

        WorkspacePill {
            required property var modelData

            barWindow: root.barWindow
            workspace: modelData
            visible: root.monitorMatches(modelData)
            onClicked: modelData.activate()
        }

    }

}
