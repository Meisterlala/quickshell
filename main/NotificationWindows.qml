pragma ComponentBehavior: Bound

import "./components"
import "./popups"
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root
    required property var service
    readonly property string fallbackScreen: Quickshell.screens.length ? Quickshell.screens[0].name : ""
    readonly property string focusedScreen: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : fallbackScreen
    readonly property string centerScreen: Quickshell.screens.some(screen => screen.name === service.centerScreen) ? service.centerScreen : fallbackScreen
    Binding {
        target: root.service
        property: "focusedScreen"
        value: root.focusedScreen
    }

    Variants {
        model: Quickshell.screens
        Scope {
            id: output
            required property var modelData
            readonly property string screenName: modelData.name
            readonly property var popups: root.service.popups.filter(entry => entry.screen === screenName || (!Quickshell.screens.some(screen => screen.name === entry.screen) && screenName === root.fallbackScreen))

            // Keep each card alive when another notification arrives or changes.
            // Replacing a JS-array model recreates hovered/dragged delegates.
            function syncPopups() {
                if (!popupCards)
                    return;
                const ids = popups.map(entry => entry.uid);
                for (let i = popupCards.count - 1; i >= 0; --i) {
                    if (!ids.includes(popupCards.get(i).uid))
                        popupCards.remove(i);
                }
                for (let i = 0; i < popups.length; ++i) {
                    const entry = popups[i];
                    let existing = i;
                    while (existing < popupCards.count && popupCards.get(existing).uid !== entry.uid)
                        ++existing;
                    const json = JSON.stringify(entry);
                    if (existing === popupCards.count) {
                        popupCards.insert(i, {
                            uid: entry.uid,
                            json: json
                        });
                    } else {
                        if (existing !== i)
                            popupCards.move(existing, i, 1);
                        if (popupCards.get(i).json !== json)
                            popupCards.setProperty(i, "json", json);
                    }
                }
            }
            onPopupsChanged: syncPopups()
            ListModel {
                id: popupCards
                Component.onCompleted: output.syncPopups()
            }

            PanelWindow {
                id: toastWindow
                screen: output.modelData
                visible: output.popups.length > 0
                color: "transparent"
                // no_screen_share applies to the whole surface, not its input
                // mask. Never make a protected notification surface full-screen.
                implicitWidth: Math.min(420, output.modelData.width - 32)
                implicitHeight: Math.max(1, toastColumn.implicitHeight)
                anchors {
                    top: true
                    right: true
                }
                margins {
                    top: 54
                    right: 16
                }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell-notifications"
                // Only cover fullscreen apps when explicitly enabled.
                WlrLayershell.layer: root.service.alwaysOnTop ? WlrLayer.Overlay : WlrLayer.Top
                // Toasts must never interrupt typing, even on hover/click.
                // Keyboard interaction belongs in the explicitly opened center.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {
                    item: toastColumn
                }

                Column {
                    id: toastColumn
                    width: toastWindow.width
                    spacing: 8
                    Repeater {
                        model: popupCards
                        NotificationCard {
                            required property string json
                            width: toastColumn.width
                            entry: JSON.parse(json)
                            service: root.service
                            compact: true
                            onInteractingChanged: root.service.hovered[entry.uid] = interacting
                            Component.onDestruction: delete root.service.hovered[entry.uid]
                        }
                    }
                }
            }

            PanelWindow {
                id: centerWindow
                readonly property NotificationCenter centerContent: centerLoader.item as NotificationCenter
                screen: output.modelData
                visible: root.service.centerOpen && output.screenName === root.centerScreen
                color: "transparent"
                implicitWidth: Math.min(540, output.modelData.width - 32)
                implicitHeight: Math.max(1, Math.min(centerContent ? centerContent.implicitHeight : 1, output.modelData.height - 70))
                anchors {
                    top: true
                    right: true
                }
                margins {
                    top: 54
                    right: 16
                }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell-notification-center"
                // Apply the same preference to the notification center.
                WlrLayershell.layer: root.service.alwaysOnTop ? WlrLayer.Overlay : WlrLayer.Top
                // Opening the center must not take focus from the current app.
                // OnDemand still permits explicitly clicking an inline reply.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

                Item {
                    anchors.fill: parent
                    // Stay open until the bell (or IPC toggle) is used again,
                    // including when the pointer/focus moves to another app.
                    Keys.onEscapePressed: root.service.centerOpen = false
                    Loader {
                        id: centerLoader
                        anchors.fill: parent
                        active: centerWindow.visible
                        sourceComponent: NotificationCenter {
                            service: root.service
                        }
                    }
                }
            }
        }
    }
}
