<?php
date_default_timezone_set('UTC');
// strtotime relative
echo date('Y-m-d H:i:s', strtotime('2024-01-15 10:00:00')), "\n";
echo date('Y-m-d H:i:s', strtotime('+1 day', strtotime('2024-01-15 10:00:00'))), "\n";
echo date('Y-m-d H:i:s', strtotime('+2 weeks', strtotime('2024-01-15 10:00:00'))), "\n";
echo date('Y-m-d H:i:s', strtotime('+1 month', strtotime('2024-01-31'))), "\n"; // Mar 02 (jan 31 + 1mo overflows)
echo date('Y-m-d H:i:s', strtotime('-1 year', strtotime('2024-02-29'))), "\n"; // 2023-03-01
echo date('Y-m-d H:i:s', strtotime('next monday', strtotime('2024-01-15'))), "\n"; // jan 22
echo date('Y-m-d H:i:s', strtotime('last friday', strtotime('2024-01-15'))), "\n"; // jan 12
echo date('Y-m-d H:i:s', strtotime('first day of next month', strtotime('2024-01-15'))), "\n"; // 2024-02-01
echo date('Y-m-d H:i:s', strtotime('last day of last month', strtotime('2024-03-15'))), "\n"; // 2024-02-29
// DateTime ops
$d = new DateTime('2024-01-15');
$d->modify('+1 day');
echo $d->format('Y-m-d'), "\n";
$d->add(new DateInterval('P2D'));
echo $d->format('Y-m-d'), "\n";
$d->sub(new DateInterval('P1M'));
echo $d->format('Y-m-d'), "\n";
// diff
$d1 = new DateTime('2024-01-15');
$d2 = new DateTime('2024-03-20');
$di = $d1->diff($d2);
echo $di->days, " ", $di->y, ":", $di->m, ":", $di->d, " invert=", $di->invert, "\n";
$di2 = $d2->diff($d1);
echo $di2->days, " ", $di2->y, ":", $di2->m, ":", $di2->d, " invert=", $di2->invert, "\n";
// timezone conversion
$d = new DateTime('2024-06-15 12:00:00', new DateTimeZone('America/New_York'));
echo $d->format('c'), "\n";
$d->setTimezone(new DateTimeZone('Asia/Tokyo'));
echo $d->format('c'), "\n";
// DST transition
$d = new DateTime('2024-03-10 01:30:00', new DateTimeZone('America/New_York'));
echo $d->format('Y-m-d H:i T'), "\n";
$d->add(new DateInterval('PT1H'));
echo $d->format('Y-m-d H:i T'), "\n"; // 03:30 EDT (skipped 02)
// negative years
echo date('Y', strtotime('1 year ago', strtotime('2000-01-01'))), "\n";
// ISO week
echo date('o-W-N', strtotime('2024-12-30')), "\n"; // 2025-01-1
echo date('o-W-N', strtotime('2024-01-01')), "\n"; // 2024-01-1
// timestamp out of range
echo date('Y-m-d', 0), "\n";
echo date('Y-m-d', -86400), "\n";
echo date('Y-m-d', 253402300799), "\n"; // 9999-12-31
// seconds since epoch
echo strtotime('2024-01-15 12:00:00 UTC'), "\n";
echo strtotime('2024-01-15T12:00:00+00:00'), "\n";
echo strtotime('2024-01-15T12:00:00+09:00'), "\n";
// custom format
$d = DateTime::createFromFormat('d/m/Y H:i', '15/01/2024 10:30');
echo $d->format('Y-m-d H:i'), "\n";
$d = DateTime::createFromFormat('!Y-m', '2024-06');
echo $d->format('Y-m-d H:i:s'), "\n"; // 2024-06-01 00:00:00 (! resets)
// localtime
$lt = localtime(strtotime('2024-01-15 12:30:45 UTC'));
print_r($lt);
$lt = localtime(strtotime('2024-01-15 12:30:45 UTC'), true);
print_r($lt);
// getdate
$gd = getdate(strtotime('2024-01-15 12:30:45 UTC'));
echo $gd['year'], "-", $gd['mon'], "-", $gd['mday'], " ", $gd['hours'], ":", $gd['minutes'], ":", $gd['seconds'], " wday=", $gd['wday'], " yday=", $gd['yday'], "\n";
// mktime
echo mktime(12, 0, 0, 1, 15, 2024), "\n"; // Jan 15 2024 12:00 local (UTC here)
echo mktime(0, 0, 0, 13, 1, 2023), "\n"; // overflow: Jan 1 2024
echo mktime(0, 0, 0, 0, 1, 2024), "\n"; // overflow: Dec 1 2023
