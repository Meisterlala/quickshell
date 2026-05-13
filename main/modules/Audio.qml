import "../components"
import QtQuick

ScriptModule {
    moduleName: "audio"
    command: "wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{ if ($3 == \"[MUTED]\") print \"󰖁\"; else printf \"%d%% \", $2 * 100 }'"
    interval: 2000
    parseJson: false
    onClickCommand: "pwvucontrol"
    onRightClickCommand: "helvum"
    onClicked: (button) => {
        if (button === Qt.MiddleButton)
            runCommand("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle");
        else if (button === Qt.LeftButton)
            runCommand(onClickCommand);
        else if (button === Qt.RightButton)
            runCommand(onRightClickCommand);
    }
}
