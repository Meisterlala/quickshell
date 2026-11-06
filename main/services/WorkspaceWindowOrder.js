// Order workspace icons by window geometry without changing the source model.
function spatialOrder(windows) {
    const positioned = [];
    const unknown = [];
    for (const window of windows) {
        const ipc = window.lastIpcObject;
        if (!ipc || !ipc.at || !ipc.size || !Number.isFinite(ipc.at[0]) || !Number.isFinite(ipc.at[1]) || !Number.isFinite(ipc.size[0]) || !Number.isFinite(ipc.size[1]) || ipc.size[0] <= 0 || ipc.size[1] <= 0) {
            unknown.push(window);
            continue;
        }
        positioned.push({
            window: window,
            x: ipc.at[0] + ipc.size[0] / 2,
            y: ipc.at[1]
        });
    }

    function addressOrder(a, b) {
        const left = a.address || "";
        const right = b.address || "";
        return left < right ? -1 : left > right ? 1 : 0;
    }

    positioned.sort((a, b) => a.x - b.x || a.y - b.y || addressOrder(a.window, b.window));
    const result = [];
    for (let start = 0; start < positioned.length; ) {
        let end = start + 1;
        // Anchor each column to its first centre, avoiding non-transitive
        // fuzzy comparators and tolerating small differences in stacked tiles.
        while (end < positioned.length && positioned[end].x - positioned[start].x <= 24)
            ++end;
        const column = positioned.slice(start, end);
        column.sort((a, b) => a.y - b.y || a.x - b.x || addressOrder(a.window, b.window));
        for (const item of column)
            result.push(item.window);
        start = end;
    }
    return result.concat(unknown.sort(addressOrder));
}
