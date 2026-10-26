import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "NotificationLogic.js" as Logic

Scope {
    id: root

    property var ipc: null
    property string focusedScreen: ""
    property string centerScreen: ""
    property bool centerOpen: false
    property int historyLimit: 100
    property int popupLimit: 4
    readonly property var entries: JSON.parse(state.entriesJson)
    readonly property alias doNotDisturb: state.dnd
    readonly property var history: entries.filter(entry => !entry.transient)
    readonly property var popups: entries.filter(entry => entry.popup).slice(0, popupLimit)
    readonly property int unreadCount: history.filter(entry => entry.unread).length
    readonly property string stateDirectory: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell"
    property bool directoryReady: false
    property bool dndTouched: false
    property string persistenceError: ""

    // Only plain data enters models and persistence. Live QObjects stay in this
    // JS map, never in ListModel roles (which can retain dangling C++ pointers).
    property var liveRefs: ({})
    property var remaining: ({})
    property var hovered: ({})

    PersistentProperties {
        id: state
        reloadableId: "main-notifications"
        // QJSValue arrays belong to their engine and cannot cross a reload.
        // Persist JSON, then parse it in the current engine instead.
        property string entriesJson: "[]"
        property bool dnd: false
        property string session: String(Date.now())
        property int serial: 0
        property bool initialized: false
    }

    function setEntries(value) {
        state.entriesJson = JSON.stringify(value);
    }

    function toggleCenter(screenName) {
        if (!centerOpen || (screenName && screenName !== centerScreen)) {
            centerScreen = screenName || focusedScreen;
            centerOpen = true;
        } else {
            centerOpen = false;
        }
    }

    function setDnd(enabled) {
        dndTouched = true;
        state.dnd = enabled;
        if (enabled)
            dismissPopups();
        saveSoon();
    }

    function markRead() {
        for (const entry of entries.filter(item => item.transient))
            hidePopup(entry.uid);
        setEntries(entries.map(entry => Object.assign({}, entry, { unread: false, popup: false })));
    }

    Connections {
        target: root.ipc
        function onPopupRequested(name) {
            if (name === "notifications")
                root.toggleCenter("");
        }
    }

    onCenterOpenChanged: {
        if (centerOpen)
            markRead();
    }
    onEntriesChanged: saveSoon()

    function entryFor(uid) {
        return entries.find(entry => entry.uid === uid);
    }

    function patch(uid, changes) {
        setEntries(entries.map(entry => entry.uid === uid ? Object.assign({}, entry, changes) : entry));
    }

    function receive(notification) {
        notification.tracked = true;
        const previous = notification.lastGeneration ? entries.find(entry =>
            entry.session === state.session && entry.sourceId === notification.id && entry.live) : null;
        const uid = previous ? previous.uid : state.session + "-" + (++state.serial);
        liveRefs[uid] = notification;
        const refresh = function() { root.refreshNotification(uid); };
        for (const name of ["summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged",
                           "imageChanged", "urgencyChanged", "expireTimeoutChanged", "actionsChanged",
                           "hasInlineReplyChanged", "inlineReplyPlaceholderChanged", "transientChanged"])
            notification[name].connect(refresh);
        notification.closed.connect(function() { root.closed(uid); });
        if (previous) {
            if (previous.popup && previous.timeout > 0)
                remaining[uid] = previous.timeout;
            refreshNotification(uid, true);
            return;
        }
        const entry = Logic.snapshot(notification, uid, state.session, Date.now());
        entry.unread = !centerOpen;
        entry.popup = !centerOpen && (!doNotDisturb || entry.urgency === 2);
        entry.screen = focusedScreen;
        if (entry.popup && entry.timeout > 0)
            remaining[uid] = entry.timeout;
        setEntries([entry].concat(entries));
        trim();
        // Transient feedback suppressed by DND must not become hidden history.
        if (entry.transient && !entry.popup)
            dismiss(uid);
    }

    function refreshNotification(uid, restoring) {
        const notification = liveRefs[uid];
        const previous = entryFor(uid);
        if (!notification || !previous)
            return;
        const entry = Logic.snapshot(notification, uid, state.session, previous.timestamp);
        entry.unread = restoring ? previous.unread : !centerOpen;
        entry.popup = restoring ? previous.popup : !centerOpen && (!doNotDisturb || entry.urgency === 2);
        entry.screen = previous.screen;
        if (!restoring && entry.popup && entry.timeout > 0)
            remaining[uid] = entry.timeout;
        patch(uid, entry);
    }

    function closed(uid) {
        delete liveRefs[uid];
        delete remaining[uid];
        delete hovered[uid];
        const entry = entryFor(uid);
        if (!entry)
            return;
        if (entry.transient)
            setEntries(entries.filter(item => item.uid !== uid));
        else
            patch(uid, { live: false, actions: [], inlineReply: false, popup: false, image: "" });
    }

    function hidePopup(uid) {
        const entry = entryFor(uid);
        delete remaining[uid];
        delete hovered[uid];
        if (entry && entry.transient) {
            const notification = liveRefs[uid];
            if (notification)
                notification.expire();
            else
                dismiss(uid);
        } else {
            patch(uid, { popup: false });
        }
    }

    function dismiss(uid) {
        const notification = liveRefs[uid];
        // Remove before closing: the synchronous closed signal must not revive it.
        setEntries(entries.filter(entry => entry.uid !== uid));
        delete liveRefs[uid];
        delete remaining[uid];
        delete hovered[uid];
        if (notification)
            notification.dismiss();
    }

    function clear() {
        for (const entry of entries.slice())
            dismiss(entry.uid);
    }

    function dismissPopups() {
        for (const entry of popups.slice())
            hidePopup(entry.uid);
    }

    function trim() {
        const excess = entries.slice(historyLimit);
        for (const entry of excess)
            dismiss(entry.uid);
        const overflow = entries.filter(entry => entry.popup).slice(popupLimit);
        for (const entry of overflow)
            hidePopup(entry.uid);
    }

    function invoke(uid, actionId) {
        const notification = liveRefs[uid];
        if (!notification)
            return false;
        // Actions can destroy their notification. Never touch the QObject
        // after invoking the action.
        const action = notification.actions.find(item => item.identifier === actionId);
        if (!action)
            return false;
        patch(uid, { popup: false, unread: false });
        action.invoke();
        return true;
    }

    function reply(uid, text) {
        const notification = liveRefs[uid];
        if (!notification || !notification.hasInlineReply || !text.trim())
            return false;
        patch(uid, { popup: false, unread: false });
        notification.sendInlineReply(text);
        return true;
    }

    function saveSoon() {
        if (state.initialized && directoryReady)
            saveTimer.restart();
    }

    function load(raw) {
        if (state.initialized)
            return;
        try {
            const saved = Logic.parseState(raw, historyLimit);
            const seen = new Set(entries.map(entry => entry.uid));
            setEntries(entries.concat(saved.entries.filter(entry => !seen.has(entry.uid))).slice(0, historyLimit));
            if (!dndTouched) {
                state.dnd = saved.dnd;
                if (saved.dnd)
                    setEntries(entries.map(entry => Object.assign({}, entry,
                        { popup: entry.popup && entry.urgency === 2 })));
            }
        } catch (error) {
            persistenceError = "Could not read saved notification history";
            console.warn(persistenceError, error);
        }
        state.initialized = true;
    }

    Process {
        command: ["mkdir", "-m", "700", "-p", root.stateDirectory]
        running: true
        onExited: (code) => {
            root.directoryReady = code === 0;
            if (code !== 0)
                root.persistenceError = "Could not create notification state directory";
        }
    }

    FileView {
        id: stateFile
        path: root.directoryReady ? root.stateDirectory + "/notifications.json" : ""
        atomicWrites: true
        printErrors: false
        onLoaded: root.load(text())
        onLoadFailed: root.load("")
        onSaveFailed: {
            root.persistenceError = "Could not save notification history";
            console.warn(root.persistenceError);
        }
    }

    Timer {
        id: saveTimer
        interval: 200
        onTriggered: stateFile.setText(JSON.stringify({ version: 1, dnd: state.dnd,
            entries: Logic.persistentEntries(root.entries, root.historyLimit) }) + "\n")
    }

    // One timer for the entire service, and no work when there are no timed
    // popups. Hover pauses the countdown, including while entering a reply.
    Timer {
        interval: 100
        repeat: true
        running: root.popups.some(entry => entry.timeout > 0)
        onTriggered: {
            for (const entry of root.popups) {
                if (entry.timeout <= 0 || root.hovered[entry.uid])
                    continue;
                root.remaining[entry.uid] = (root.remaining[entry.uid] || entry.timeout) - interval;
                if (root.remaining[entry.uid] <= 0)
                    root.hidePopup(entry.uid);
            }
        }
    }

    NotificationServer {
        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        inlineReplySupported: true
        // Render plain text deliberately; no remote HTML images or link fetching.
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        onNotification: notification => root.receive(notification)
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { root.toggleCenter(""); }
        function close(): void { root.centerOpen = false; }
        function toggleDnd(): bool { root.setDnd(!root.doNotDisturb); return root.doNotDisturb; }
        function setDnd(enabled: bool): void { root.setDnd(enabled); }
        function clear(): void { root.clear(); }
        function dismissAll(): void { root.dismissPopups(); }
        function getState(): string {
            return JSON.stringify({ dnd: root.doNotDisturb, open: root.centerOpen,
                unread: root.unreadCount, count: root.history.length, popups: root.popups.length,
                persistenceError: root.persistenceError });
        }
    }
}
