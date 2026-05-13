import "./components"
import "./modules"
import QtQuick
import Quickshell
import Quickshell.Hyprland

Scope {
    id: root

    required property var ipc

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
                color: theme.alpha(theme.base, 0.4)
            }

            Row {
                id: left

                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Workspaces {
                    barWindow: bar
                }

            }

            ActiveWindow {
                anchors.centerIn: parent
                maxWidth: Math.max(280, parent.width * 0.36)
            }

            Row {
                id: right

                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                NotificationModule {
                    moduleVisible: root.isPrimary(bar.screen)
                }

                Tray {
                    visible: root.isPrimary(bar.screen)
                    barWindow: bar
                }

                ScriptModule {
                    moduleVisible: root.isPrimary(bar.screen)
                    ipc: root.ipc
                    moduleName: "fritz-traffic"
                    command: "/home/misti/.config/waybar/fritz_traffic.py"
                    interval: 10000
                    onClickCommand: "qs ipc -c main call bar refreshModule fritz-traffic"
                }

                ScriptModule {
                    moduleVisible: root.isPrimary(bar.screen)
                    ipc: root.ipc
                    moduleName: "nvidia-driver"
                    command: "/home/misti/.config/waybar/nvidia-driver.py"
                    interval: 60000
                }

                ScriptModule {
                    moduleVisible: root.isPrimary(bar.screen)
                    ipc: root.ipc
                    moduleName: "systemd-failed-units"
                    command: "/home/misti/.config/waybar/failed-units.sh"
                    interval: 10000
                    onClickCommand: "/home/misti/.config/waybar/restart-failed.sh"
                }

                ScriptModule {
                    moduleVisible: root.isPrimary(bar.screen)
                    ipc: root.ipc
                    moduleName: "scrcpy-active"
                    command: "/home/misti/.config/waybar/scrcpy-active.sh"
                    interval: 2000
                    onClickCommand: "/home/misti/.config/waybar/scrcpy-active.sh --kill"
                }

                ScriptModule {
                    moduleVisible: root.isPrimary(bar.screen)
                    ipc: root.ipc
                    moduleName: "updates"
                    command: "/home/misti/.config/waybar/arch_updates.py"
                    interval: 900000
                    onClickCommand: "ghostty -e bash -lc 'paru -Syu; echo; read -rp \"Press Enter to close...\"'"
                }

                ScriptModule {
                    moduleVisible: root.isPrimary(bar.screen)
                    ipc: root.ipc
                    moduleName: "codex"
                    command: "/home/misti/.config/waybar/codex_usage.py"
                    interval: 300000
                }

                ScriptModule {
                    moduleVisible: root.isPrimary(bar.screen)
                    ipc: root.ipc
                    moduleName: "habits"
                    command: "/home/misti/.local/bin/habits-waybar"
                    interval: 30000
                    onClickCommand: "/home/misti/.local/bin/habits-waybar --toggle"
                }

                Audio {
                    moduleVisible: root.isPrimary(bar.screen)
                }

                ScriptModule {
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "load"
                    command: "awk '{print $1 \" \" $2 \" \" $3}' /proc/loadavg"
                    interval: 10000
                    parseJson: false
                }

                ScriptModule {
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "hypridle"
                    command: "/home/misti/.config/waybar/idle_inhibit.py"
                    interval: 5000
                }

                ScriptModule {
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "gpu"
                    command: "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | awk '{printf \"%2d%% 󰢮\", $1}'"
                    interval: 5000
                    parseJson: false
                }

                ScriptModule {
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "cpu"
                    command: "top -bn1 | awk '/Cpu\\(s\\)/ {printf \"%2d%% \", 100 - $8}'"
                    interval: 3000
                    parseJson: false
                }

                ScriptModule {
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "memory"
                    command: "free | awk '/Mem:/ {printf \"%2d%% \", $3/$2*100}'"
                    interval: 5000
                    parseJson: false
                }

                ScriptModule {
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "k8s-alerts"
                    command: "/home/misti/.config/waybar/k8s-alerts.py"
                    interval: 60000
                }

                ScriptModule {
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "weight"
                    command: "/home/misti/opencode/weight-unlock/show_weight_waybar.py"
                    interval: 60000
                    onClickCommand: "/home/misti/opencode/weight-unlock/show_weight_waybar.py --toggle"
                }

                ScriptModule {
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "sleep"
                    textOverride: ""
                    onClickCommand: "systemctl suspend"
                }

                ScriptModule {
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "garage-longhorn"
                    command: "/home/misti/.config/waybar/garage-status.sh longhorn-backup L"
                    interval: 10000
                }

                ScriptModule {
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "garage-velero"
                    command: "/home/misti/.config/waybar/garage-status.sh velero V"
                    interval: 10000
                }

                ScriptModule {
                    moduleVisible: root.isSecondary(bar.screen)
                    ipc: root.ipc
                    moduleName: "garage-kopia"
                    command: "/home/misti/.config/waybar/garage-status.sh kopia K"
                    interval: 10000
                }

                Clock {
                    barWindow: bar
                }

            }

        }

    }

}
