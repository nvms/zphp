<?php
$base = 1750000245; // 2025-06-15 12:30:45 UTC (Sunday)

// --- RFC 2822 ---
echo strtotime("Wed, 15 Jan 2025 10:30:45 +0000") . "\n";
echo strtotime("Wed, 31 Dec 2025 23:59:59 +0000") . "\n";
echo strtotime("15 Jan 2025 10:30:45 +0000") . "\n";
echo strtotime("Wed, 15 Jan 2025 10:30:45 GMT") . "\n";
echo strtotime("Wed, 15 Jan 2025 10:30:45 -0500") . "\n";
echo strtotime("Tue, 01 Jul 2025 00:00:00 +0000") . "\n";

// --- timezone suffixes on YYYY-MM-DD ---
echo strtotime("2025-01-15 10:30:00 UTC") . "\n";
echo strtotime("2025-01-15 10:30:00 GMT") . "\n";
echo strtotime("2025-01-15 10:30:00 EST") . "\n";
echo strtotime("2025-01-15 10:30:00 PST") . "\n";
echo strtotime("2025-01-15 10:30:00 +0530") . "\n";
echo strtotime("2025-01-15 10:30:00 -0500") . "\n";
echo strtotime("2025-01-15 10:30:00 +00:00") . "\n";

// --- ordinal weekday of month ---
echo strtotime("first Monday of January 2025") . "\n";
echo strtotime("second Tuesday of March 2025") . "\n";
echo strtotime("third Friday of June 2025") . "\n";
echo strtotime("fourth Wednesday of September 2025") . "\n";
echo strtotime("last Friday of December 2025") . "\n";
echo strtotime("last Monday of February 2025") . "\n";
echo strtotime("first Sunday of March 2025") . "\n";

// --- ordinal weekday with next/last month ---
echo strtotime("first Monday of next month", $base) . "\n";
echo strtotime("second Friday of next month", $base) . "\n";
echo strtotime("last Wednesday of last month", $base) . "\n";
echo strtotime("third Thursday of this month", $base) . "\n";

// --- edge cases ---
echo strtotime("fifth Monday of March 2025") . "\n";
echo strtotime("first Thursday of January 2025") . "\n";
echo strtotime("last Saturday of February 2025") . "\n";
