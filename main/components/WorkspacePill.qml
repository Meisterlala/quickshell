import ".."
import "../services"
import QtQuick
import Quickshell
import Quickshell.Hyprland

Rectangle {
    id: root

    required property var workspace
    property var barWindow: null
    property int horizontalPadding: 20
    property int minimumWidth: 54
    property int iconSize: 18
    property int iconSpacing: 3
    readonly property list<var> windows: Hyprland.toplevels.values.filter(toplevel => workspace && toplevel.workspace && toplevel.workspace.id === workspace.id)
    readonly property bool occupied: windows.length > 0

    signal clicked(int button)

    function appClass(toplevel) {
        if (!toplevel)
            return "";

        if (toplevel.wayland && toplevel.wayland.appId)
            return toplevel.wayland.appId;

        if (toplevel.lastIpcObject) {
            if (toplevel.lastIpcObject.class)
                return toplevel.lastIpcObject.class;

            if (toplevel.lastIpcObject.initialClass)
                return toplevel.lastIpcObject.initialClass;
        }

        return "";
    }

    function desktopIcon(toplevel) {
        if (!toplevel)
            return "";

        const app = appClass(toplevel);
        return app ? Quickshell.iconPath(app, true) : "";
    }

    width: Math.max(minimumWidth, icons.implicitWidth + horizontalPadding)
    implicitWidth: Math.max(minimumWidth, icons.implicitWidth + horizontalPadding)
    implicitHeight: 34
    radius: 8
    color: mouse.containsMouse ? theme.surface2 : (workspace && workspace.active ? theme.surface2 : (occupied ? theme.alpha(theme.surface0, 0.8) : theme.alpha(theme.surface0, 0.2)))
    border.color: occupied ? theme.alpha(theme.text, 0.1) : "transparent"
    border.width: 1

    Theme {
        id: theme
    }

    WorkspaceIconMap {
        id: iconMap
    }

    Row {
        id: icons

        anchors.centerIn: parent
        spacing: root.iconSpacing

        Repeater {
            model: root.windows

            Item {
                required property var modelData
                readonly property string glyph: iconMap.iconFor(modelData)
                readonly property string iconSource: root.desktopIcon(modelData)

                width: root.iconSize
                height: root.iconSize

                Image {
                    anchors.fill: parent
                    source: parent.iconSource
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                    visible: parent.glyph.length === 0 && parent.iconSource.length > 0
                }

                Text {
                    anchors.centerIn: parent
                    text: parent.glyph
                    color: root.workspace && root.workspace.urgent ? theme.red : theme.text
                    font.family: theme.fontFamily
                    font.pixelSize: theme.barFontPixelSize
                    textFormat: Text.PlainText
                    visible: parent.glyph.length > 0
                }

                Text {
                    anchors.centerIn: parent
                    text: "?"
                    color: root.workspace && root.workspace.urgent ? theme.red : theme.text
                    font.family: theme.fontFamily
                    font.pixelSize: theme.barFontPixelSize
                    textFormat: Text.PlainText
                    visible: parent.glyph.length === 0 && parent.iconSource.length === 0
                }
            }

        }

    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        onClicked: (mouse) => root.clicked(mouse.button)
    }
}
