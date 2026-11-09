pragma ComponentBehavior: Bound

import ".."
import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Widgets

PopupWindow {
    id: root

    required property var menu
    property var parentMenu: null
    property bool anchorHovered: false
    readonly property bool cascadeHovered: anchorHovered || menuHover.hovered || (submenuLoader.item !== null && submenuLoader.item.cascadeHovered)
    property int activeIndex: -1
    property int submenuIndex: -1
    readonly property int padding: 6
    readonly property var entries: opener.children.values
    readonly property bool hasSubmenus: entries.some(entry => !entry.isSeparator && entry.hasChildren)
    readonly property int trailingWidth: hasSubmenus ? 22 : 0
    readonly property int availableHeight: screen ? Math.max(40, screen.height - 64) : 600
    property real measuredWidth: 0

    signal dismissed()

    function submenuEdge() {
        // Use the actual placement, including compositor FlipX adjustments.
        // Once a level flips left, its descendants prefer left as well.
        // Query on opening, after the parent popup has been positioned.
        if (parentMenu && mapFromItem(parentMenu.contentItem, 0, 0).x > 0)
            return Edges.Left;
        return Edges.Right;
    }

    function focusMenu() {
        keyboardScope.forceActiveFocus();
    }

    function closeAll() {
        if (parentMenu)
            parentMenu.closeAll();
        else
            dismissed();
    }

    function closeSubmenu() {
        submenuIndex = -1;
        submenuLoader.active = false;
    }

    function openSubmenu(index, keyboard) {
        const row = rows.itemAt(index);
        if (!row || !row.modelData.enabled || !row.modelData.hasChildren)
            return;
        if (submenuIndex !== index) {
            closeSubmenu();
            submenuIndex = index;
            // Load lazily: no recursive component tree or unopened DBus menus.
            submenuLoader.setSource(Qt.resolvedUrl("TrayMenu.qml"), {
                menu: row.modelData,
                parentMenu: root
            });
            submenuLoader.active = true;
        }
        if (keyboard && submenuLoader.item) {
            submenuLoader.item.focusMenu();
            submenuLoader.item.moveSelection(1);
        }
    }

    function activate(index) {
        const entry = entries[index];
        if (!entry || entry.isSeparator || !entry.enabled)
            return;
        if (entry.hasChildren)
            openSubmenu(index, true);
        else {
            entry.triggered();
            closeAll();
        }
    }

    function moveSelection(direction) {
        hoverTimer.stop();
        closeSubmenu();
        for (let step = 1; step <= entries.length; ++step) {
            const start = activeIndex < 0 && direction < 0 ? 0 : activeIndex;
            const index = (start + direction * step + entries.length) % entries.length;
            const entry = entries[index];
            if (entry.enabled && !entry.isSeparator) {
                activeIndex = index;
                const row = rows.itemAt(index);
                if (row.y < scroll.contentY)
                    scroll.contentY = row.y;
                else if (row.y + row.height > scroll.contentY + scroll.height)
                    scroll.contentY = row.y + row.height - scroll.height;
                return;
            }
        }
    }

    function measure() {
        let widest = 0;
        for (let i = 0; i < rows.count; ++i) {
            const row = rows.itemAt(i);
            if (row)
                widest = Math.max(widest, row.naturalWidth);
        }
        measuredWidth = widest;
    }

    implicitWidth: Math.ceil(Math.min(screen ? screen.width - 16 : 420, Math.max(180, Math.min(420, measuredWidth + padding * 2))))
    implicitHeight: Math.min(availableHeight, column.implicitHeight + padding * 2)
    color: "transparent"
    // No input grab: clicks outside must reach the underlying application.
    grabFocus: false
    anchor.adjustment: PopupAdjustment.FlipX | PopupAdjustment.SlideY
    onVisibleChanged: {
        if (visible) {
            activeIndex = -1;
            scroll.contentY = 0;
            keyboardScope.forceActiveFocus();
        } else {
            hoverTimer.stop();
            closeSubmenu();
            if (!parentMenu)
                dismissed();
        }
    }

    HoverHandler {
        id: menuHover
        parent: root.contentItem
    }

    Timer {
        // Briefly leaving the cascade is harmless; re-entry cancels dismissal.
        interval: 400
        running: !root.parentMenu && root.visible && !root.cascadeHovered
        onTriggered: root.closeAll()
    }

    Theme { id: theme }
    QsMenuOpener {
        id: opener
        menu: root.visible ? root.menu : null
    }

    Timer {
        id: hoverTimer
        interval: 180
        onTriggered: {
            if (root.submenuIndex !== root.activeIndex)
                root.closeSubmenu();
            root.openSubmenu(root.activeIndex, false);
        }
    }

    // The child is anchored to the parent popup, never to the bar's coordinate space.
    Loader {
        id: submenuLoader
        active: false
        onLoaded: {
            const row = rows.itemAt(root.submenuIndex);
            item.anchor.window = root;
            item.anchor.rect.x = 0;
            item.anchor.rect.y = row.mapToItem(root.contentItem, 0, 0).y - root.padding;
            item.anchor.rect.width = root.width;
            item.anchor.rect.height = 1;
            const side = root.submenuEdge();
            item.anchor.edges = Edges.Top | side;
            item.anchor.gravity = Edges.Bottom | side;
            item.visible = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: theme.alpha(theme.base, 0.98)
        border.width: 1
        border.color: theme.alpha(theme.text, 0.16)

        FocusScope {
            id: keyboardScope
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Escape:
                    root.closeAll();
                    break;
                case Qt.Key_Left:
                    if (root.parentMenu) {
                        const parent = root.parentMenu;
                        parent.closeSubmenu();
                        parent.focusMenu();
                    }
                    break;
                case Qt.Key_Up:
                    root.moveSelection(-1);
                    break;
                case Qt.Key_Down:
                    root.moveSelection(1);
                    break;
                case Qt.Key_Right:
                    root.openSubmenu(root.activeIndex, true);
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    root.activate(root.activeIndex);
                    break;
                default:
                    return;
                }
                event.accepted = true;
            }

            Flickable {
                id: scroll
                anchors.fill: parent
                anchors.margins: root.padding
                contentWidth: width
                contentHeight: column.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onContentYChanged: root.closeSubmenu()
                Controls.ScrollBar.vertical: Controls.ScrollBar {
                    policy: scroll.contentHeight > scroll.height ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff
                }

                Column {
                    id: column
                    width: scroll.width

                    Repeater {
                        id: rows
                        model: opener.children
                        onItemAdded: Qt.callLater(root.measure)
                        onItemRemoved: Qt.callLater(root.measure)

                        Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property string label: modelData.isSeparator ? "" : modelData.text.replace(/&&/g, "\u0000").replace(/&/g, "").replace(/\u0000/g, "&")
                            readonly property bool hasCheck: !modelData.isSeparator && modelData.buttonType !== QsMenuButtonType.None
                            readonly property bool hasIcon: !modelData.isSeparator && modelData.icon.length > 0
                            readonly property int leadingWidth: (hasCheck ? 24 : 0) + (hasIcon ? 24 : 0)
                            readonly property real naturalWidth: modelData.isSeparator ? 0 : Math.ceil(Math.max(textMetrics.width, textMetrics.advanceWidth)) + 22 + leadingWidth + root.trailingWidth
                            readonly property bool selected: root.activeIndex === index || root.submenuIndex === index
                            onNaturalWidthChanged: Qt.callLater(root.measure)
                            width: column.width
                            height: modelData.isSeparator ? 11 : 32
                            radius: 5
                            color: selected && modelData.enabled && !modelData.isSeparator ? theme.alpha(theme.surface1, 0.8) : "transparent"

                            TextMetrics {
                                id: textMetrics
                                text: row.label
                                font.family: theme.fontFamily
                                font.pixelSize: theme.menuFontPixelSize
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 10
                                width: parent.width - 20
                                height: 1
                                color: theme.alpha(theme.text, 0.12)
                                visible: row.modelData.isSeparator
                            }

                            Text {
                                x: 10
                                width: 16
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: row.modelData.buttonType === QsMenuButtonType.RadioButton ? "●" : row.modelData.checkState === Qt.PartiallyChecked ? "−" : "✓"
                                visible: !row.modelData.isSeparator && row.modelData.buttonType !== QsMenuButtonType.None && row.modelData.checkState !== Qt.Unchecked
                                color: row.modelData.enabled ? theme.green : theme.overlay1
                                font.pixelSize: 13
                            }

                            IconImage {
                                x: 10 + (row.hasCheck ? 24 : 0)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16
                                height: 16
                                source: row.modelData.isSeparator ? "" : row.modelData.icon
                                visible: !row.modelData.isSeparator && row.modelData.icon.length > 0
                                opacity: row.modelData.enabled ? 1 : 0.45
                            }

                            Text {
                                x: 10 + row.leadingWidth
                                width: Math.max(0, parent.width - x - 10 - root.trailingWidth)
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.label
                                textFormat: Text.PlainText
                                visible: !row.modelData.isSeparator
                                color: row.modelData.enabled ? theme.text : theme.overlay1
                                font.family: theme.fontFamily
                                font.pixelSize: theme.menuFontPixelSize
                                elide: Text.ElideRight
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "›"
                                visible: !row.modelData.isSeparator && row.modelData.hasChildren
                                color: row.modelData.enabled ? theme.subtext0 : theme.overlay1
                                font.pixelSize: 20
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: {
                                    if (row.modelData.isSeparator || !row.modelData.enabled)
                                        return;
                                    root.activeIndex = row.index;
                                    hoverTimer.restart();
                                }
                                onClicked: {
                                    hoverTimer.stop();
                                    root.activate(row.index);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
