<?php
// covers: time, date, mktime, strtotime, checkdate, getdate,
//   date arithmetic, relative dates, timestamp formatting, date format specifiers

// --- basic timestamp ---

echo "=== Basic Timestamp ===\n";

$ts = mktime(12, 30, 45, 6, 15, 2024);
echo "mktime(12,30,45,6,15,2024): " . $ts . "\n";
echo "date('Y-m-d H:i:s', ts): " . date('Y-m-d H:i:s', $ts) . "\n";
echo "date('D, d M Y', ts): " . date('D, d M Y', $ts) . "\n";
echo "date('U', ts) == ts: " . (date('U', $ts) == $ts ? 'yes' : 'no') . "\n";

// --- date format specifiers ---

echo "\n=== Date Format ===\n";

$fixed = mktime(9, 5, 3, 3, 7, 2024);
echo "Y: " . date('Y', $fixed) . "\n";
echo "y: " . date('y', $fixed) . "\n";
echo "m: " . date('m', $fixed) . "\n";
echo "n: " . date('n', $fixed) . "\n";
echo "d: " . date('d', $fixed) . "\n";
echo "j: " . date('j', $fixed) . "\n";
echo "H: " . date('H', $fixed) . "\n";
echo "G: " . date('G', $fixed) . "\n";
echo "i: " . date('i', $fixed) . "\n";
echo "s: " . date('s', $fixed) . "\n";
echo "A: " . date('A', $fixed) . "\n";
echo "g: " . date('g', $fixed) . "\n";
echo "N: " . date('N', $fixed) . "\n";
echo "w: " . date('w', $fixed) . "\n";
echo "t: " . date('t', $fixed) . "\n";
echo "L: " . date('L', $fixed) . "\n";

// --- checkdate ---

echo "\n=== Checkdate ===\n";

echo "checkdate(12, 31, 2024): " . (checkdate(12, 31, 2024) ? 'valid' : 'invalid') . "\n";
echo "checkdate(2, 29, 2024): " . (checkdate(2, 29, 2024) ? 'valid' : 'invalid') . "\n";
echo "checkdate(2, 29, 2023): " . (checkdate(2, 29, 2023) ? 'valid' : 'invalid') . "\n";
echo "checkdate(13, 1, 2024): " . (checkdate(13, 1, 2024) ? 'valid' : 'invalid') . "\n";
echo "checkdate(4, 31, 2024): " . (checkdate(4, 31, 2024) ? 'valid' : 'invalid') . "\n";

// --- getdate ---

echo "\n=== Getdate ===\n";

$info = getdate($ts);
echo "year: " . $info['year'] . "\n";
echo "mon: " . $info['mon'] . "\n";
echo "mday: " . $info['mday'] . "\n";
echo "hours: " . $info['hours'] . "\n";
echo "minutes: " . $info['minutes'] . "\n";
echo "seconds: " . $info['seconds'] . "\n";
echo "wday: " . $info['wday'] . "\n";

// --- strtotime absolute ---

echo "\n=== Strtotime Absolute ===\n";

echo "2024-06-15: " . date('Y-m-d', strtotime('2024-06-15')) . "\n";
echo "2024-06-15 14:30:00: " . date('Y-m-d H:i:s', strtotime('2024-06-15 14:30:00')) . "\n";
echo "06/15/2024: " . date('Y-m-d', strtotime('06/15/2024')) . "\n";
echo "15 June 2024: " . date('Y-m-d', strtotime('15 June 2024')) . "\n";
echo "June 15, 2024: " . date('Y-m-d', strtotime('June 15, 2024')) . "\n";
echo "@0: " . date('Y-m-d H:i:s', strtotime('@0')) . "\n";
echo "@1718451045: " . date('Y-m-d', strtotime('@1718451045')) . "\n";

// --- strtotime relative from fixed base ---

echo "\n=== Strtotime Relative ===\n";

$base = strtotime('2024-06-15 12:00:00');

echo "+1 day: " . date('Y-m-d', strtotime('+1 day', $base)) . "\n";
echo "-3 days: " . date('Y-m-d', strtotime('-3 days', $base)) . "\n";
echo "+1 month: " . date('Y-m-d', strtotime('+1 month', $base)) . "\n";
echo "-2 months: " . date('Y-m-d', strtotime('-2 months', $base)) . "\n";
echo "+1 year: " . date('Y-m-d', strtotime('+1 year', $base)) . "\n";
echo "+1 week: " . date('Y-m-d', strtotime('+1 week', $base)) . "\n";

// --- strtotime keywords ---

echo "\n=== Strtotime Keywords ===\n";

echo "today from base: " . date('H:i:s', strtotime('today', $base)) . "\n";
echo "yesterday from base: " . date('Y-m-d', strtotime('yesterday', $base)) . "\n";
echo "tomorrow from base: " . date('Y-m-d', strtotime('tomorrow', $base)) . "\n";
echo "midnight from base: " . date('H:i:s', strtotime('midnight', $base)) . "\n";
echo "noon from base: " . date('H:i:s', strtotime('noon', $base)) . "\n";

// --- mktime edge cases ---

echo "\n=== Mktime Edge Cases ===\n";

$jan1 = mktime(0, 0, 0, 1, 1, 2024);
$dec31 = mktime(23, 59, 59, 12, 31, 2024);
echo "Jan 1: " . date('Y-m-d', $jan1) . "\n";
echo "Dec 31: " . date('Y-m-d', $dec31) . "\n";

$leap = mktime(0, 0, 0, 2, 29, 2024);
echo "Feb 29 2024 (leap): " . date('Y-m-d', $leap) . "\n";

$dec = mktime(0, 0, 0, 12, 1, 2024);
echo "Dec 1: " . date('Y-m-d', $dec) . "\n";

// --- date arithmetic ---

echo "\n=== Date Arithmetic ===\n";

$start = mktime(0, 0, 0, 1, 1, 2024);
$end = mktime(0, 0, 0, 12, 31, 2024);
$diff_days = ($end - $start) / 86400;
echo "days in 2024: " . $diff_days . "\n";

$hour_later = $base + 3600;
echo "hour later: " . date('H:i', $hour_later) . "\n";

$week_seconds = 7 * 24 * 60 * 60;
echo "week from base: " . date('Y-m-d', $base + $week_seconds) . "\n";

// --- formatting patterns ---

echo "\n=== Format Patterns ===\n";

$sample = mktime(15, 45, 30, 11, 25, 2024);
echo "US format: " . date('m/d/Y', $sample) . "\n";
echo "EU format: " . date('d.m.Y', $sample) . "\n";
echo "12-hour: " . date('g:i A', $sample) . "\n";
echo "full: " . date('Y-m-d H:i:s', $sample) . "\n";

echo "\nDone.\n";
