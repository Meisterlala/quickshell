import QtQuick
import QtTest
import "../../main/components"
import "../../main/components/CalendarDates.js" as CalendarDates

Item {
    width: 380
    height: 360

    CalendarMonth {
        id: calendar
        width: 352
        today: new Date(2026, 9, 25, 19, 0)
        onDayClicked: day => selectedDay = selectedDay === day ? "" : day
    }

    TestCase {
        name: "CalendarMonth"
        when: windowShown

        function init() {
            calendar.showToday();
            calendar.selectedDay = "";
            wait(0); // Let Repeater dispose of the previous month's delegates.
            verify(waitForPolish(calendar));
        }

        function test_clickDay() {
            const day = findChild(calendar, "calendarDay_2026-10-12");
            verify(day !== null);
            mouseClick(day, day.width / 2, day.height / 2);
            compare(calendar.selectedDay, "2026-10-12");
            verify(day.isSelected);
            const today = findChild(calendar, "calendarDay_2026-10-25");
            verify(today.isToday);
            verify(!today.isSelected);
            mouseClick(day, day.width / 2, day.height / 2);
            compare(calendar.selectedDay, "");
            verify(!day.isSelected);
        }

        function test_selectionSurvivesMonthNavigation() {
            calendar.dayClicked("2026-10-12");
            calendar.shiftMonth(1);
            compare(calendar.selectedDay, "2026-10-12");
            calendar.shiftMonth(-1);
            wait(0);
            verify(waitForPolish(calendar));
            verify(findChild(calendar, "calendarDay_2026-10-12").isSelected);
        }

        function test_filterSelectedDay() {
            const midnight = new Date(2026, 9, 25).getTime();
            const followingMidnight = new Date(2026, 9, 26).getTime();
            const events = [
                { title: "past today", start: midnight + 1000, end: midnight + 2000 },
                { title: "overnight", start: midnight - 1000, end: midnight + 1000 },
                { title: "all day", start: midnight, end: followingMidnight },
                { title: "task", start: midnight, end: midnight },
                { title: "ends at midnight", start: midnight - 2000, end: midnight },
                { title: "tomorrow", start: followingMidnight, end: followingMidnight + 1000 }
            ];
            const filtered = CalendarDates.eventsForDay(events, "2026-10-25");
            compare(filtered.length, 4);
            compare(filtered.map(event => event.title).join(","), "past today,overnight,all day,task");
            compare(CalendarDates.eventsForDay(events, "2026-10-27").length, 0);
        }

        function test_filterDstBoundary() {
            const nextDay = new Date(2026, 2, 30, 0, 15).getTime();
            compare(CalendarDates.eventsForDay([{start: nextDay, end: nextDay + 1000}], "2026-03-29").length, 0);
        }

        function test_currentMonth() {
            compare(calendar.monthKey, "2026-10");
            compare(calendar.cells.length, 35); // No unused sixth row.
            compare(calendar.cells[3], 1); // Thursday, Monday-first.
            compare(calendar.dateKey(25), "2026-10-25");
        }

        function test_yearRolloverAndToday() {
            calendar.shiftMonth(2);
            compare(calendar.monthKey, "2026-12");
            calendar.shiftMonth(1);
            compare(calendar.monthKey, "2027-01");
            calendar.shiftMonth(-1);
            compare(calendar.monthKey, "2026-12");
            calendar.showToday();
            compare(calendar.monthKey, "2026-10");
        }

        function test_leapYear() {
            calendar.viewMonth = new Date(2028, 1, 1);
            verify(calendar.cells.indexOf(29) >= 0);
            verify(calendar.cells.indexOf(30) < 0);
        }

        function test_sixWeekMonth() {
            calendar.viewMonth = new Date(2026, 2, 1);
            compare(calendar.cells.length, 42);
            compare(calendar.cells[6], 1);
        }
    }
}
