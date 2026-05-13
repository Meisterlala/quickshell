import ".."
import QtQuick
import Quickshell.Hyprland

Text {
    id: root

    property var barWindow: null
    property int maxWidth: 420
    property var lastActiveByWorkspace: ({})

    readonly property var monitor: barWindow && barWindow.screen ? Hyprland.monitorFor(barWindow.screen) : null
    readonly property var workspace: monitor ? Hyprland.workspaces.values.find(workspace => workspace.monitor && workspace.monitor.name === monitor.name && workspace.active) : null
    readonly property list<var> workspaceWindows: Hyprland.toplevels.values.filter(toplevel => workspace && toplevel.workspace && toplevel.workspace.id === workspace.id)

    function cleanTitle(title) {
        if (!title)
            return "";

        return title.replace(/(.*) — Zen Browser$/, "$1");
    }

    function normalizeAddress(address) {
        return (address || "").replace(/^0x/, "");
    }

    function rememberToplevel(toplevel) {
        if (!toplevel || !toplevel.workspace || !toplevel.address)
            return;

        const next = Object.assign({}, lastActiveByWorkspace);
        next[toplevel.workspace.id] = toplevel.address;
        lastActiveByWorkspace = next;
    }

    function toplevelForAddress(address) {
        const normalized = normalizeAddress(address);
        return Hyprland.toplevels.values.find(toplevel => normalizeAddress(toplevel.address) === normalized);
    }

    function workspaceTitle() {
        if (workspaceWindows.length === 0)
            return "";

        const active = workspaceWindows.find(toplevel => toplevel.activated);
        if (active)
            return cleanTitle(active.title);

        const lastAddress = workspace ? lastActiveByWorkspace[workspace.id] : "";
        const lastActive = workspaceWindows.find(toplevel => normalizeAddress(toplevel.address) === normalizeAddress(lastAddress));
        return cleanTitle((lastActive || workspaceWindows[0]).title);
    }

    text: workspaceTitle()
    color: theme.text
    font.family: theme.fontFamily
    font.pixelSize: theme.activeWindowFontPixelSize
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
    width: Math.min(maxWidth, implicitWidth)

    Theme {
        id: theme
    }

    Component.onCompleted: rememberToplevel(Hyprland.activeToplevel)

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "activewindowv2")
                return;

            const args = event.parse(1);
            root.rememberToplevel(root.toplevelForAddress(args[0]));
        }
    }
}
