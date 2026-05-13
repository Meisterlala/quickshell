import ".."
import QtQuick

Rectangle {
    id: root

    radius: 16
    color: theme.alpha(theme.mantle, 0.96)
    border.color: theme.alpha(theme.text, 0.12)
    border.width: 1

    Theme {
        id: theme
    }

}
