<?php
// use a fixed base timestamp: 2025-06-15 12:30:45 UTC (Sunday)
$base = 1750000245;

// "now"
echo strtotime("now", $base) . "\n";

// "today" - midnight of base day
echo strtotime("today", $base) . "\n";

// "yesterday" - midnight of previous day
echo strtotime("yesterday", $base) . "\n";

// "tomorrow" - midnight of next day
echo strtotime("tomorrow", $base) . "\n";

// "midnight"
echo strtotime("midnight", $base) . "\n";

// "noon"
echo strtotime("noon", $base) . "\n";

// numeric relative with sign
echo strtotime("+3 days", $base) . "\n";
echo strtotime("-1 day", $base) . "\n";
echo strtotime("+2 hours", $base) . "\n";
echo strtotime("-30 minutes", $base) . "\n";
echo strtotime("+1 week", $base) . "\n";
echo strtotime("+1 month", $base) . "\n";
echo strtotime("-1 year", $base) . "\n";
echo strtotime("+10 seconds", $base) . "\n";

// "ago" suffix
echo strtotime("3 days ago", $base) . "\n";
echo strtotime("2 hours ago", $base) . "\n";
echo strtotime("1 year ago", $base) . "\n";

// next/last weekday
echo strtotime("next Monday", $base) . "\n";
echo strtotime("next Friday", $base) . "\n";
echo strtotime("last Monday", $base) . "\n";
echo strtotime("last Saturday", $base) . "\n";

// next/last month/year
echo strtotime("next month", $base) . "\n";
echo strtotime("last month", $base) . "\n";
echo strtotime("next year", $base) . "\n";
echo strtotime("last year", $base) . "\n";

// next/last week
echo strtotime("next week", $base) . "\n";
echo strtotime("last week", $base) . "\n";

// YYYY-MM-DD
echo strtotime("2025-01-15") . "\n";
echo strtotime("2025-12-31") . "\n";

// YYYY-MM-DD HH:MM:SS
echo strtotime("2025-01-15 10:30:00") . "\n";

// ISO 8601 with T separator
echo strtotime("2025-01-15T10:30:00") . "\n";

// @timestamp
echo strtotime("@1234567890") . "\n";

// US date format MM/DD/YYYY
echo strtotime("01/15/2025") . "\n";
echo strtotime("12/31/2025") . "\n";

// textual month dates
echo strtotime("January 15, 2025") . "\n";
echo strtotime("Jan 15, 2025") . "\n";
echo strtotime("Jan 15 2025") . "\n";
echo strtotime("15 Jan 2025") . "\n";
echo strtotime("December 31, 2025") . "\n";

// first day of / last day of
echo strtotime("first day of next month", $base) . "\n";
echo strtotime("last day of next month", $base) . "\n";
echo strtotime("first day of last month", $base) . "\n";
echo strtotime("last day of last month", $base) . "\n";
echo strtotime("first day of this month", $base) . "\n";

// first/last day of named month
echo strtotime("first day of January 2025") . "\n";
echo strtotime("last day of February 2025") . "\n";
echo strtotime("last day of December 2025") . "\n";

// weekday name alone (next occurrence)
echo strtotime("Monday", $base) . "\n";
echo strtotime("Friday", $base) . "\n";

// multiple relative parts
echo strtotime("+1 year 2 months", $base) . "\n";
echo strtotime("+1 year 2 months 3 days", $base) . "\n";

// plurals
echo strtotime("+5 seconds", $base) . "\n";
echo strtotime("+3 minutes", $base) . "\n";
echo strtotime("+2 weeks", $base) . "\n";
