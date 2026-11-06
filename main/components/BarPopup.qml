import QtQuick
import Quickshell

// Shared positioning for module popups. Content and sizing stay with the module.
PopupWindow {
    id: root

    required property var barWindow
    required property Item anchorItem
    property bool shown: false
    readonly property int margin: 8

    anchor.window: barWindow
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeY
    anchor.rect.x: barWindow ? Math.max(margin, Math.min(barWindow.width - width - margin,
        anchorItem.mapToItem(null, 0, 0).x + anchorItem.width / 2 - width / 2)) : 0
    anchor.rect.y: barWindow ? barWindow.height + margin : anchorItem.height + margin
    anchor.rect.width: anchorItem.width
    anchor.rect.height: anchorItem.height
    color: "transparent"
    // Popups must not grab the keyboard away from the active application.
    grabFocus: false
    visible: barWindow !== null && anchorItem.visible && shown
}
