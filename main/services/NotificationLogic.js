// Plain-data notification helpers.
function plainText(value) {
    return String(value || "").replace(/<br\s*\/?\s*>/gi, "\n")
        .replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
        .replace(/&quot;/g, '"').replace(/&apos;|&#39;/g, "'").replace(/&amp;/g, "&");
}

function safeImage(value) {
    const text = String(value || "");
    // Never fetch a sender-controlled remote URL, including from body markup.
    if (/^(file:\/\/\/|image:\/\/)/.test(text) || text.startsWith("/"))
        return text;
    return "";
}

function duration(urgency, requested) {
    if (urgency === 2 || requested === 0)
        return 0;
    return requested > 0 ? requested : urgency === 0 ? 5000 : 10000;
}

function snapshot(notification, uid, session, now) {
    const actions = [];
    for (const action of notification.actions || [])
        actions.push({ id: String(action.identifier), text: String(action.text) });
    return {
        uid: uid, session: session, sourceId: notification.id, timestamp: now,
        app: String(notification.appName || "Notification"),
        icon: String(notification.appIcon || ""), image: safeImage(notification.image),
        summary: String(notification.summary || ""), body: plainText(notification.body),
        urgency: Number(notification.urgency), transient: !!notification.transient,
        timeout: duration(Number(notification.urgency), Number(notification.expireTimeout)),
        actions: actions, inlineReply: !!notification.hasInlineReply,
        replyPlaceholder: String(notification.inlineReplyPlaceholder || "Reply…"),
        live: true, unread: true, popup: false, screen: ""
    };
}

function archive(entry) {
    return Object.assign({}, entry, {
        sourceId: -1, session: "", live: false, actions: [], inlineReply: false,
        popup: false, image: ""
    });
}

function persistentEntries(entries, limit) {
    return entries.filter(entry => !entry.transient).slice(0, limit).map(archive);
}

function parseState(raw, limit) {
    const value = JSON.parse(raw || "{}");
    const entries = Array.isArray(value.entries) ? value.entries : [];
    return {
        dnd: value.dnd === true,
        alwaysOnTop: value.alwaysOnTop === true,
        entries: entries.filter(entry => entry && typeof entry.uid === "string"
            && typeof entry.summary === "string" && typeof entry.body === "string"
            && Number.isFinite(entry.timestamp) && !entry.transient)
            .slice(0, limit).map(archive)
    };
}

if (typeof module !== "undefined")
    module.exports = { plainText, safeImage, duration, snapshot, archive, persistentEntries, parseState };
