<?php
date_default_timezone_set("UTC");

// date format specifiers
$ts = mktime(14, 30, 45, 6, 15, 2025); // Jun 15, 2025 14:30:45 UTC
echo date("Y-m-d H:i:s", $ts), "\n";
echo date("d/m/Y", $ts), "\n";
echo date("D, d M Y", $ts), "\n";
echo date("l, jS F Y", $ts), "\n";
echo date("g:i A", $ts), "\n";
echo date("g:i a", $ts), "\n";
echo date("H:i:s", $ts), "\n";
echo date("h:i:s", $ts), "\n";
echo date("U", $ts), "\n";

// week-related
echo date("W", $ts), "\n";    // ISO week
echo date("N", $ts), "\n";    // ISO weekday 1-7
echo date("w", $ts), "\n";    // 0-6 weekday
echo date("z", $ts), "\n";    // day of year (0-based)

// year variants
echo date("Y", $ts), "\n";    // 4-digit
echo date("y", $ts), "\n";    // 2-digit
echo date("o", $ts), "\n";    // ISO week year

// month
echo date("m", $ts), "\n";    // 01-12
echo date("n", $ts), "\n";    // 1-12
echo date("M", $ts), "\n";    // Jan
echo date("F", $ts), "\n";    // January

// timezone in date format
echo date("e", $ts), "\n";   // UTC
echo date("T", $ts), "\n";    // UTC
echo date("P", $ts), "\n";    // +00:00
echo date("O", $ts), "\n";    // +0000
echo date("Z", $ts), "\n";    // 0 seconds

// daylight saving
echo date("I", $ts), "\n";   // 0 in UTC

// various formats
echo date("c", $ts), "\n";   // ISO 8601: 2025-06-15T14:30:45+00:00
echo date("r", $ts), "\n";   // RFC 2822
echo date("u", $ts), "\n";  // microseconds (0)
echo date("v", $ts), "\n";  // milliseconds (0)

// strtotime relative
echo date("Y-m-d", strtotime("2025-06-15 + 1 day")), "\n";
echo date("Y-m-d", strtotime("2025-06-15 - 1 week")), "\n";
echo date("Y-m-d", strtotime("2025-06-15 + 2 months")), "\n";
echo date("Y-m-d", strtotime("2025-06-15 + 1 year")), "\n";

// ordinal
echo date("Y-m-d", strtotime("first day of next month", strtotime("2025-06-15"))), "\n";
echo date("Y-m-d", strtotime("last day of this month", strtotime("2025-06-15"))), "\n";
echo date("Y-m-d", strtotime("next monday", strtotime("2025-06-15"))), "\n";
echo date("Y-m-d", strtotime("midnight", strtotime("2025-06-15 14:30"))), "\n";

// ISO 8601 strings
echo date("Y-m-d H:i:s", strtotime("2025-06-15T14:30:45Z")), "\n";
echo date("Y-m-d H:i:s", strtotime("2025-06-15T14:30:45+00:00")), "\n";
echo date("Y-m-d H:i:s", strtotime("2025-06-15T14:30:45+05:30")), "\n";

// RFC 2822
echo date("Y-m-d H:i:s", strtotime("Sun, 15 Jun 2025 14:30:45 GMT")), "\n";

// US format
echo date("Y-m-d", strtotime("06/15/2025")), "\n";

// timezone shifts
$tz_ny = new DateTimeZone("America/New_York");
$d = new DateTime("2025-06-15 12:00:00", $tz_ny);
echo $d->format("Y-m-d H:i:s e"), "\n"; // 2025-06-15 12:00:00 America/New_York
$d->setTimezone(new DateTimeZone("UTC"));
echo $d->format("Y-m-d H:i:s e"), "\n"; // 2025-06-15 16:00:00 UTC (EDT = -4)

// DST boundary (US: DST starts second Sunday of March)
$d_before = new DateTime("2025-03-09 01:00:00", $tz_ny);
echo $d_before->format("e P"), "\n";

$d_after = new DateTime("2025-03-09 03:00:00", $tz_ny);
echo $d_after->format("e P"), "\n";

// add 24 hours over DST boundary
$d = new DateTime("2025-03-08 12:00:00", $tz_ny);
$d->add(new DateInterval("PT24H"));
echo $d->format("Y-m-d H:i:s P"), "\n"; // adds 24 wall hours -> may differ in offset

// add 1 day over DST (calendar-based)
$d = new DateTime("2025-03-08 12:00:00", $tz_ny);
$d->add(new DateInterval("P1D"));
echo $d->format("Y-m-d H:i:s P"), "\n"; // 2025-03-09 12:00:00 EDT

// ISO week boundary
$d = new DateTime("2025-01-01");
echo $d->format("W o"), "\n"; // 01 2025

$d = new DateTime("2024-12-30"); // Mon of week 1 of 2025? Actually week 1 of 2025
echo $d->format("W o"), "\n";

$d = new DateTime("2025-12-29"); // week 1 of 2026 (PHP/ISO)
echo $d->format("W o"), "\n";

// checkdate
var_dump(checkdate(2, 29, 2024));
var_dump(checkdate(2, 29, 2025));
var_dump(checkdate(13, 1, 2025));
var_dump(checkdate(0, 1, 2025));

// getdate
$info = getdate(mktime(0, 0, 0, 1, 1, 2025));
echo $info["weekday"], " ", $info["month"], " ", $info["mday"], " ", $info["year"], "\n";

// date_create_from_format
$d = DateTime::createFromFormat("d/m/Y", "15/06/2025");
echo $d ? $d->format("Y-m-d") : "fail", "\n";

$d = DateTime::createFromFormat("Y-m-d H:i:s", "2025-06-15 14:30:45");
echo $d->format("U"), "\n";

// invalid format returns false
$d = DateTime::createFromFormat("Y-m-d", "not-a-date");
var_dump($d);

// timestamp conversions
$d = (new DateTime())->setTimestamp(1750000000);
echo $d->setTimezone(new DateTimeZone("UTC"))->format("Y-m-d H:i:s"), "\n";

// negative timestamps
echo date("Y-m-d", -1000000), "\n"; // 1969-12-20

// get/set DateInterval
$i = new DateInterval("P1Y2M3DT4H5M6S");
echo "$i->y $i->m $i->d $i->h $i->i $i->s\n";

// DateInterval format
echo $i->format("%y-%m-%d %h:%i:%s"), "\n";
echo $i->format("%Y/%M/%D %H:%I:%S"), "\n";
echo $i->format("%R%y"), "\n"; // +1
$i->invert = 1;
echo $i->format("%R%y"), "\n"; // -1

// diff with %a
$a = new DateTime("2025-01-01");
$b = new DateTime("2025-12-31");
$diff = $a->diff($b);
echo $diff->format("%a days"), "\n";

// %r for negative
echo $diff->format("%r%a"), "\n"; // (empty if positive)

// week year boundary
$d = new DateTime("2024-12-30"); // Monday of week 1 of 2025
echo $d->format("o-W-N"), "\n";

// timezone abbreviations
echo date("T", strtotime("2025-06-15 12:00:00")), "\n"; // UTC
