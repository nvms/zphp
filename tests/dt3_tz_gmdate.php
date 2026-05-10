<?php
date_default_timezone_set("UTC");

// DateTimeZone with invalid id
try { new DateTimeZone("Not/A/Zone"); echo "no\n"; } catch (\Exception $e) { echo "tz-err\n"; }

$tz = new DateTimeZone("America/New_York");
echo $tz->getName(), "\n";

$tz = new DateTimeZone("UTC");
echo $tz->getName(), "\n";

// fixed offset
$tz = new DateTimeZone("+05:00");
echo $tz->getName(), "\n";

// DateInterval format specifiers
$i = new DateInterval("P1Y2M3DT4H5M6S");
echo $i->format("%y-%m-%d %h:%i:%s"), "\n";
echo $i->format("%Y-%M-%D %H:%I:%S"), "\n"; // zero-padded
echo $i->format("%a"), "\n"; // total days

// %a only valid after diff
$d1 = new DateTime("2024-01-01");
$d2 = new DateTime("2024-06-15");
echo $d1->diff($d2)->format("%a"), "\n"; // 166

// %R sign
echo $d1->diff($d2)->format("%R%a"), "\n"; // +166
echo $d2->diff($d1)->format("%R%a"), "\n"; // -166

// %r (only for negative)
echo $d2->diff($d1)->format("%r%a"), "\n"; // -166
echo $d1->diff($d2)->format("%r%a"), "\n"; // 166 (no sign)

// DatePeriod with EXCLUDE_START_DATE
$start = new DateTime("2024-01-01");
$end = new DateTime("2024-01-04");
$interval = new DateInterval("P1D");
$period = new DatePeriod($start, $interval, $end);
foreach ($period as $d) echo $d->format("Y-m-d"), "|";
echo "\n";

$period = new DatePeriod($start, $interval, $end, DatePeriod::EXCLUDE_START_DATE);
foreach ($period as $d) echo $d->format("Y-m-d"), "|";
echo "\n";

// DatePeriod count
$start = new DateTime("2024-01-01");
$period = new DatePeriod($start, new DateInterval("P1D"), 5);
$count = 0;
foreach ($period as $d) $count++;
echo $count, "\n"; // 6 (start + 5)

// gmdate vs date
$ts = mktime(12, 0, 0, 6, 15, 2024);
echo gmdate("Y-m-d H:i:s", $ts), "\n";
echo date("Y-m-d H:i:s", $ts), "\n";

date_default_timezone_set("America/New_York");
echo gmdate("Y-m-d H:i:s", $ts), "\n"; // unchanged
echo date("Y-m-d H:i:s", $ts), "\n"; // shifted
date_default_timezone_set("UTC");

// microtime
$t = microtime(true);
echo gettype($t), ":", $t > 0 ? "pos" : "neg", "\n";
echo strpos((string)$t, ".") !== false ? "float-dot" : "no", "\n";

$s = microtime();
$parts = explode(" ", $s);
echo count($parts), "\n"; // 2

// hrtime
$h = hrtime();
echo gettype($h), "\n"; // array (in PHP 7.4+)
echo count($h), "\n"; // 2 [seconds, nanoseconds]

$ht = hrtime(true);
echo gettype($ht), "\n"; // integer (or string for huge values?)

// time()
$t = time();
echo gettype($t), ":", $t > 1700000000 ? "recent\n" : "old\n";

// timestamp arithmetic
$now = time();
$tomorrow = $now + 86400;
echo $tomorrow - $now, "\n"; // 86400

// strtotime relative
echo date("Y-m-d", strtotime("+7 days", mktime(0, 0, 0, 6, 15, 2024))), "\n"; // 2024-06-22
echo date("Y-m-d", strtotime("last day of next month", mktime(0, 0, 0, 1, 15, 2024))), "\n"; // 2024-02-29
echo date("Y-m-d", strtotime("first sunday of next month", mktime(0, 0, 0, 1, 15, 2024))), "\n"; // 2024-02-04

// date format specifiers
$d = new DateTime("2024-06-15 12:30:45");
echo $d->format("Y-m-d\TH:i:s"), "\n";
echo $d->format("c"), "\n"; // ISO 8601
echo $d->format("U"), "\n"; // unix
echo $d->format("r"), "\n"; // RFC 2822
echo $d->format("u"), "\n"; // microseconds
echo $d->format("N"), "\n"; // ISO weekday (1-7)
echo $d->format("w"), "\n"; // weekday (0-6)
echo $d->format("z"), "\n"; // day of year
echo $d->format("W"), "\n"; // ISO week
echo $d->format("L"), "\n"; // leap year
echo $d->format("e"), "\n"; // timezone
echo $d->format("T"), "\n"; // timezone abbrev
echo $d->format("P"), "\n"; // timezone offset
echo $d->format("O"), "\n"; // timezone offset
echo $d->format("Z"), "\n"; // offset in seconds
