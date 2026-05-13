import QtQuick
import Quickshell.Hyprland

Text {
    id: root

    property int maxWidth: 420

    function cleanTitle(title) {
        if (!title)
            return "";

        return title.replace(/(.*) — Zen Browser$/, "$1");
    }

    text: cleanTitle(Hyprland.activeToplevel ? Hyprland.activeToplevel.title : "")
    color: "#cdd6f4"
    font.family: "FiraCode Nerd Font"
    font.pixelSize: 14
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
    width: Math.min(maxWidth, implicitWidth)
}
