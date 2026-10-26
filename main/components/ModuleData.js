// Helpers shared by script-backed modules. Keep these independent of QML objects.
function clampPercent(value) {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(0, Math.min(100, number)) : 0;
}

function parseObject(output) {
    // Helpers may log before emitting their final JSON line.
    const lines = String(output).trim().split("\n").filter(line => line.trim().length > 0);
    const value = JSON.parse(lines[lines.length - 1]);
    if (value === null || typeof value !== "object" || Array.isArray(value))
        throw new Error("Expected a JSON object");
    return value;
}

function formatText(format, text, icon) {
    // A replacement callback keeps '$&' literal and never formats placeholders
    // that came from the script's text or icon.
    return format.replace(/\{\}|\{icon\}/g, placeholder => placeholder === "{}" ? text : icon);
}

if (typeof module !== "undefined")
    module.exports = { clampPercent, parseObject, formatText };
