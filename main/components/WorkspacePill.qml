import ".."
import "../services"
import "../services/WorkspaceWindowOrder.js" as WindowOrder
import QtQuick
import QtQuick.Effects
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
    readonly property list<var> spatialWindows: WindowOrder.spatialOrder(Hyprland.toplevels.values.filter(toplevel => workspace && toplevel.workspace && toplevel.workspace.id === workspace.id))
    property list<var> windows: []

    // Geometry/title refreshes should not rebuild icon delegates unless the
    // membership or spatial order actually changed.
    onSpatialWindowsChanged: syncWindowOrder()

    function syncWindowOrder() {
        if (windows.length !== spatialWindows.length
                || spatialWindows.some((window, index) => window !== windows[index]))
            windows = spatialWindows;
    }
    readonly property bool occupied: windows.length > 0
    readonly property var desktopEntries: DesktopEntries.applications.values

    signal clicked(int button)

    Component.onCompleted: {
        syncWindowOrder();
        WorkspaceWindowOrder.registerPill(root);
    }
    Component.onDestruction: WorkspaceWindowOrder.unregisterPill(root)

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
        if (!app)
            return "";

        // The built-in lookup does not match short window IDs to reverse-DNS
        // desktop IDs. Also match desktop metadata, reacting when entries load.
        const entries = root.desktopEntries;
        const key = app.toLowerCase().replace(/\.desktop$/, "");
        const entry = DesktopEntries.heuristicLookup(app)
            || entries.find(candidate => candidate.startupClass.toLowerCase() === key)
            || entries.find(candidate => candidate.name.toLowerCase() === key)
            || entries.find(candidate => candidate.id.toLowerCase().endsWith("." + key));
        const icon = entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : "";
        return icon || Quickshell.iconPath(app, true);
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
                id: windowIcon

                required property var modelData
                readonly property bool urgent: modelData ? modelData.urgent : false
                readonly property string glyph: iconMap.iconFor(modelData)
                readonly property string iconSource: root.desktopIcon(modelData)

                width: root.iconSize
                height: root.iconSize

                SequentialAnimation on opacity {
                    running: windowIcon.visible && windowIcon.urgent
                    loops: Animation.Infinite
                    onRunningChanged: {
                        if (!running)
                            windowIcon.opacity = 1;
                    }

                    NumberAnimation {
                        from: 1
                        to: 0.2
                        duration: 1000
                        easing.type: Easing.InOutSine
                    }

                    NumberAnimation {
                        from: 0.2
                        to: 1
                        duration: 1000
                        easing.type: Easing.InOutSine
                    }
                }

                Image {
                    anchors.fill: parent
                    source: parent.iconSource
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                    visible: parent.glyph.length === 0 && parent.iconSource.length > 0
                    layer.enabled: windowIcon.urgent
                    layer.effect: MultiEffect {
                        colorization: 1
                        colorizationColor: theme.red
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: parent.glyph
                    color: windowIcon.urgent ? theme.red : theme.text
                    font.family: theme.fontFamily
                    font.pixelSize: theme.barFontPixelSize
                    textFormat: Text.PlainText
                    visible: parent.glyph.length > 0
                }

                Text {
                    anchors.centerIn: parent
                    text: "?"
                    color: windowIcon.urgent ? theme.red : theme.text
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
