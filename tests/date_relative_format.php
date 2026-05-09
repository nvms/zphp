<?php
date_default_timezone_set('UTC');

// strtotime relative formats
echo date('Y-m-d', strtotime("2024-01-15")), "\n";
echo date('Y-m-d', strtotime("+1 day", strtotime("2024-01-15"))), "\n";
echo date('Y-m-d', strtotime("+1 week", strtotime("2024-01-15"))), "\n";
echo date('Y-m-d', strtotime("-1 month", strtotime("2024-03-15"))), "\n";
echo date('Y-m-d', strtotime("next monday", strtotime("2024-01-15"))), "\n"; // 2024-01-22
echo date('Y-m-d', strtotime("next friday", strtotime("2024-01-15"))), "\n"; // 2024-01-19
echo date('Y-m-d', strtotime("last sunday", strtotime("2024-01-15"))), "\n"; // 2024-01-14
echo date('Y-m-d', strtotime("first day of next month", strtotime("2024-01-15"))), "\n"; // 2024-02-01
echo date('Y-m-d', strtotime("last day of this month", strtotime("2024-02-15"))), "\n"; // 2024-02-29
echo date('Y-m-d', strtotime("+2 weeks +3 days", strtotime("2024-01-01"))), "\n"; // 2024-01-18
echo date('Y-m-d H:i', strtotime("tomorrow", strtotime("2024-01-15 10:30:00"))), "\n"; // next day 00:00
echo date('Y-m-d', strtotime("yesterday", strtotime("2024-01-15"))), "\n"; // 2024-01-14
echo date('Y-m-d', strtotime("today", strtotime("2024-06-20"))), "\n"; // 2024-06-20
echo date('Y-m-d', strtotime("midnight", strtotime("2024-06-20 14:30"))), "\n";
echo date('Y-m-d', strtotime("noon", strtotime("2024-06-20 14:30"))), "\n";

// DateTime modify relative
$d = new DateTime('2024-01-15');
$d->modify('next monday');
echo $d->format('Y-m-d'), "\n"; // 2024-01-22

$d = new DateTime('2024-01-15');
$d->modify('+2 weeks +3 days');
echo $d->format('Y-m-d'), "\n"; // 2024-02-01

$d = new DateTime('2024-01-31');
$d->modify('+1 month');
echo $d->format('Y-m-d'), "\n"; // 2024-03-02 (overflow)

$d = new DateTime('2024-03-15');
$d->modify('first day of this month');
echo $d->format('Y-m-d'), "\n"; // 2024-03-01

// date format chars
$ts = strtotime('2024-06-15 14:30:45 UTC');
echo date('W', $ts), "\n"; // ISO week
echo date('U', $ts), "\n"; // unix timestamp
echo date('Z', $ts), "\n"; // tz offset (0 for UTC)
echo date('S', $ts), "\n"; // ordinal suffix (th)
echo date('t', $ts), "\n"; // days in month (30 for June)
echo date('L', $ts), "\n"; // leap year (1)
echo date('o', $ts), "\n"; // ISO year
echo date('N', $ts), "\n"; // ISO weekday number (6 = Saturday)
echo date('w', $ts), "\n"; // weekday number (6 = Saturday in 0-6)
echo date('z', $ts), "\n"; // day of year (0-based: Jan 1 = 0)
echo date('B', $ts), "\n"; // Swatch internet time (might be unsupported)
echo date('I', $ts), "\n"; // 1 if DST, 0 otherwise
echo date('r', $ts), "\n"; // RFC 2822
echo date('c', $ts), "\n"; // ISO 8601
echo date('e', $ts), "\n"; // tz id
echo date('T', $ts), "\n"; // tz abbrev (UTC)
echo date('P', $ts), "\n"; // +00:00
echo date('O', $ts), "\n"; // +0000

// suffix special cases
echo date('jS', strtotime('2024-01-01')), "\n"; // 1st
echo date('jS', strtotime('2024-01-02')), "\n"; // 2nd
echo date('jS', strtotime('2024-01-03')), "\n"; // 3rd
echo date('jS', strtotime('2024-01-11')), "\n"; // 11th
echo date('jS', strtotime('2024-01-21')), "\n"; // 21st
echo date('jS', strtotime('2024-01-22')), "\n"; // 22nd
echo date('jS', strtotime('2024-01-23')), "\n"; // 23rd

// days in month at boundaries
echo date('t', strtotime('2024-02-15')), "\n"; // 29 (leap)
echo date('t', strtotime('2023-02-15')), "\n"; // 28
echo date('t', strtotime('2024-01-15')), "\n"; // 31
echo date('t', strtotime('2024-04-15')), "\n"; // 30

// array_filter with mode flags edge cases
print_r(array_filter([], fn($v) => $v));
print_r(array_filter([0, 1, 2], fn($v) => $v > 0, 0)); // 0 = no flag (USE_VALUE default)
print_r(array_filter([1 => "a", 2 => "b"], fn($k) => $k < 2, ARRAY_FILTER_USE_KEY));
print_r(array_filter(["a" => 1], fn($v, $k) => $v > 0 && $k === "a", ARRAY_FILTER_USE_BOTH));

// array_walk callback signature mismatch
$a = [1, 2, 3];
array_walk($a, function($v) { /* missing key */ }); // PHP allows
echo "walked ok\n";
$a = [1, 2, 3];
array_walk($a, function(&$v, $k, $extra) { $v = "$v($extra)"; }, "ext");
print_r($a);

// in_array similar to array_search w/ closure (not callable)
var_dump(in_array(2, [1, 2, 3]));
var_dump(in_array("2", [1, 2, 3], true));
var_dump(in_array("2", [1, 2, 3]));
