.pragma library

function eventsForDay(events, day) {
    const parts = day.split("-").map(Number);
    const start = new Date(parts[0], parts[1] - 1, parts[2]).getTime();
    // Construct the following local midnight, not a fixed 24-hour offset (DST).
    const end = new Date(parts[0], parts[1] - 1, parts[2] + 1).getTime();
    return events.filter(event => event.start < end && (event.end > start || event.start >= start));
}
