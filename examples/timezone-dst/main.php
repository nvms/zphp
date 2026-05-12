<?php
// covers: DateTimeZone offsets across DST transitions, setTimezone() arithmetic,
//   format specifiers e/T/P/O/Z, mktime in local time, timezone_offset_get

date_default_timezone_set('UTC');

echo "=== current default tz ===\n";
echo "tz: " . date_default_timezone_get() . "\n";

echo "\n=== UTC vs local-time offsets ===\n";
$zones = ['UTC', 'America/New_York', 'Europe/London', 'Asia/Tokyo'];
$ref = new DateTimeImmutable('2026-06-15 12:00:00', new DateTimeZone('UTC'));
foreach ($zones as $z) {
    $tz = new DateTimeZone($z);
    $offset = $tz->getOffset($ref);
    $hours = sprintf("%+d:%02d", intdiv($offset, 3600), abs($offset % 3600) / 60);
    echo sprintf("  %-20s %s\n", $z, $hours);
}

echo "\n=== DST aware: summer vs winter offset ===\n";
$ny = new DateTimeZone('America/New_York');
$summer = new DateTimeImmutable('2026-07-15', $ny);
$winter = new DateTimeImmutable('2026-01-15', $ny);
echo "summer offset: " . $ny->getOffset($summer) / 3600 . "h\n";
echo "winter offset: " . $ny->getOffset($winter) / 3600 . "h\n";

echo "\n=== convert between zones preserves instant ===\n";
$ts = '2026-06-15 14:30:00';
$utc = new DateTimeImmutable($ts, new DateTimeZone('UTC'));
$nyt = $utc->setTimezone($ny);
$tokyo = $utc->setTimezone(new DateTimeZone('Asia/Tokyo'));
echo "UTC:   " . $utc->format('Y-m-d H:i:s P') . "\n";
echo "NYC:   " . $nyt->format('Y-m-d H:i:s P') . "\n";
echo "Tokyo: " . $tokyo->format('Y-m-d H:i:s P') . "\n";
echo "all same instant: " . ($utc->getTimestamp() === $nyt->getTimestamp() && $utc->getTimestamp() === $tokyo->getTimestamp() ? "yes" : "no") . "\n";

echo "\n=== format with timezone-related specifiers ===\n";
$d = new DateTimeImmutable('2026-06-15 14:30:00', $ny);
echo "P (offset h:m):  " . $d->format('P') . "\n";
echo "O (offset hm):   " . $d->format('O') . "\n";
echo "Z (offset s):    " . $d->format('Z') . "\n";
echo "T (abbrev):      " . $d->format('T') . "\n";
echo "e (identifier):  " . $d->format('e') . "\n";

echo "\n=== mktime in local time vs UTC ===\n";
date_default_timezone_set('America/New_York');
$ts_local = mktime(12, 0, 0, 7, 15, 2026); // noon NY time
date_default_timezone_set('UTC');
$same_utc_clock = mktime(12, 0, 0, 7, 15, 2026); // noon UTC
$diff = $same_utc_clock - $ts_local;
echo "delta hours: " . $diff / 3600 . "\n";
date_default_timezone_set('UTC');

echo "\n=== DateTime arithmetic: 1 month \"later\" ===\n";
$start = new DateTimeImmutable('2026-01-31', new DateTimeZone('UTC'));
$plus1m = $start->add(new DateInterval('P1M'));
echo "Jan 31 + 1 month: " . $plus1m->format('Y-m-d') . "\n";  // March 3 (overflow)

$plus30d = $start->add(new DateInterval('P30D'));
echo "Jan 31 + 30 days: " . $plus30d->format('Y-m-d') . "\n"; // Mar 2

echo "\n=== leap year handling ===\n";
$feb29 = new DateTimeImmutable('2024-02-29');
echo "Feb 29 2024 valid: " . $feb29->format('Y-m-d') . "\n";
$plus_year = $feb29->add(new DateInterval('P1Y'));
echo "+1 year: " . $plus_year->format('Y-m-d') . "\n"; // overflow handling
$leap = (int)$feb29->format('L');
echo "is leap year: " . ($leap === 1 ? "yes" : "no") . "\n";

echo "\n=== unix timestamp round-trips across zones ===\n";
$ny_str = '2026-06-15 09:00:00';
$ny_dt = new DateTimeImmutable($ny_str, $ny);
$utc_dt = (new DateTimeImmutable())->setTimestamp($ny_dt->getTimestamp());
echo "ny:  $ny_str (ts=" . $ny_dt->getTimestamp() . ")\n";
echo "utc reconstruction: " . $utc_dt->format('Y-m-d H:i:s P') . "\n";

echo "\n=== difference within a single offset (no DST transition) ===\n";
$start = new DateTimeImmutable('2026-07-15 09:00:00', $ny);
$end   = new DateTimeImmutable('2026-07-15 17:30:00', $ny);
$diff = $start->diff($end);
echo "between: " . $diff->format('%h hours %i minutes') . "\n";

echo "\ndone\n";
