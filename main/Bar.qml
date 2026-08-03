import "./components"
import "./modules"
import QtQuick
import Quickshell
import Quickshell.Hyprland

Scope {
    id: root

    required property var ipc
    property bool alternativeMode: false

    function isPrimary(screen) {
        return screen && screen.name === "DP-3";
    }

    function isSecondary(screen) {
        return screen && screen.name === "DP-2";
    }

    Theme {
        id: theme
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar

            required property var modelData

            screen: modelData
            implicitHeight: 38
            color: "transparent"

            anchors {
                top: true
                left: true
                right: true
            }

            Rectangle {
                anchors.fill: parent
                color: theme.alpha(theme.base, 0.25)
            }

            Row {
                id: left

                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Workspaces {
                    barWindow: bar
                }
            }

            ActiveWindow {
                anchors.centerIn: parent
                barWindow: bar
                maxWidth: Math.max(280, parent.width * 0.5)
            }

            Row {
                id: right

                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                NotificationModule {
                    barWindow: bar
                    moduleVisible: root.isPrimary(bar.screen)
                }

                Tray {
                    visible: root.isPrimary(bar.screen)
                    barWindow: bar
                }

                FritzTraffic {
                    barWindow: bar
                    moduleVisible: root.isPrimary(bar.screen)
                    ipc: root.ipc
                    interval: 10000
                }

                SystemdFailedUnits {
                    barWindow: bar
                    moduleVisible: root.isPrimary(bar.screen)
                    ipc: root.ipc
                    interval: 10000
                }

                Updates {
                    barWindow: bar
                    moduleVisible: root.isPrimary(bar.screen)
                    ipc: root.ipc
                    interval: 900000
                }

                CodexUsage {
                    barWindow: bar
                    moduleVisible: root.isPrimary(bar.screen)
                }

                Habits {
                    barWindow: bar
                    moduleVisible: root.isPrimary(bar.screen) && !root.alternativeMode
                    ipc: root.ipc
                    interval: 15000
                    onAlternativeModeRequested: root.alternativeMode = true
                }

                Audio {
                    barWindow: bar
                    moduleVisible: root.isPrimary(bar.screen)
                }

                ScriptModule {
                    barWindow: bar
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "hypridle"
                    command: "/home/misti/.config/waybar/idle_inhibit.py"
                    interval: 5000
                    format: "{} 󰒲"
                }

                LlamaModels {
                    barWindow: bar
                    moduleVisible: root.isSecondary(bar.screen)
                }

                Gpu {
                    barWindow: bar
                    moduleVisible: root.isSecondary(bar.screen)
                    interval: 5000
                    hoverInterval: 1000
                }

                Cpu {
                    barWindow: bar
                    moduleVisible: root.isSecondary(bar.screen)
                    interval: 3000
                }

                Memory {
                    barWindow: bar
                    moduleVisible: root.isSecondary(bar.screen)
                    interval: 5000
                }

                K8sAlerts {
                    barWindow: bar
                    moduleVisible: root.isSecondary(bar.screen)
                }

                ScriptModule {
                    barWindow: bar
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "sleep"
                    textOverride: ""
                    onClickCommand: "systemctl suspend"
                }

                ScriptModule {
                    barWindow: bar
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "garage-longhorn"
                    command: "/home/misti/.config/waybar/garage-status.sh longhorn-backup L"
                    interval: 10000
                }

                ScriptModule {
                    barWindow: bar
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "garage-velero"
                    command: "/home/misti/.config/waybar/garage-status.sh velero V"
                    interval: 10000
                }

                ScriptModule {
                    barWindow: bar
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "garage-kopia"
                    command: "/home/misti/.config/waybar/garage-status.sh kopia K"
                    interval: 10000
                }

                Clock {
                    barWindow: bar
                    alternativeMode: root.alternativeMode
                    onAlternativeModeToggled: root.alternativeMode = !root.alternativeMode
                }
            }
        }
    }
}
