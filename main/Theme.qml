import QtQuick

QtObject {
    readonly property string rosewater: "#f5e0dc"
    readonly property string red: "#f38ba8"
    readonly property string yellow: "#f9e2af"
    readonly property string green: "#a6e3a1"
    readonly property string sky: "#89dceb"
    readonly property string text: "#cdd6f4"
    readonly property string subtext0: "#a6adc8"
    readonly property string overlay1: "#7f849c"
    readonly property string surface2: "#585b70"
    readonly property string surface1: "#45475a"
    readonly property string surface0: "#313244"
    readonly property string base: "#1e1e2e"
    readonly property string mantle: "#181825"
    readonly property string crust: "#11111b"

    function alpha(hex, opacity) {
        const clean = hex.replace("#", "");
        const value = Math.round(opacity * 255).toString(16).padStart(2, "0");
        return `#${value}${clean}`;
    }

    function classColor(name) {
        if (name === "critical" || name === "error")
            return red;

        if (name === "warning" || name === "users")
            return yellow;

        if (name === "upload")
            return green;

        if (name === "delete")
            return red;

        return text;
    }

}
