pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Scope {
    id: root

    // One refresh source shared by every monitor and workspace pill.
    property var consumers: []
    readonly property bool needed: consumers.some(pill => pill.visible && pill.windows.length > 1)

    function registerPill(pill) {
        consumers = consumers.concat([pill]);
    }

    function unregisterPill(pill) {
        consumers = consumers.filter(candidate => candidate !== pill);
    }

    onNeededChanged: {
        if (needed)
            refresh.restart();
        else
            refresh.stop();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (!root.needed)
                return;

            // Ignore title/urgency changes and duplicate legacy event variants.
            switch (event.name) {
            case "openwindow":
            case "closewindow":
            case "movewindowv2":
            case "moveworkspacev2":
            case "workspacev2":
            case "activewindowv2":
            case "changefloatingmode":
            case "fullscreen":
            case "monitoradded":
            case "monitorremoved":
            case "configreloaded":
            case "togglegroup":
            case "moveintogroup":
            case "moveoutofgroup":
                refresh.restart();
            }
        }
    }

    Timer {
        id: refresh
        interval: 120
        onTriggered: Hyprland.refreshToplevels()
    }

    // Hyprland has no general geometry-change event (e.g. drag or swap).
    // Only poll while a visible consumer actually needs spatial ordering.
    Timer {
        interval: 2000
        repeat: true
        running: root.needed
        onTriggered: {
            if (!refresh.running)
                Hyprland.refreshToplevels();
        }
    }
}
