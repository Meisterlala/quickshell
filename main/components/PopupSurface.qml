import ".."
import QtQuick

Rectangle {
    id: root

    radius: 16
    color: theme.alpha(theme.surface1, 0.85)
    border.color: theme.alpha(theme.text, 0.12)
    border.width: 1

    Theme {
        id: theme
    }

}
