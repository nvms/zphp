<?php

// add/sub interval - calendar-aware
$d = new DateTime('2024-01-01');
$d->add(new DateInterval('P1M'));
echo $d->format('Y-m-d') . "\n"; // Feb 1

$d = new DateTime('2024-01-01');
$d->add(new DateInterval('P1M2D'));
echo $d->format('Y-m-d') . "\n"; // Feb 3

$d = new DateTime('2024-01-31');
$d->add(new DateInterval('P1M'));
echo $d->format('Y-m-d') . "\n"; // Mar 2 (rolls forward)

$d = new DateTime('2024-03-31');
$d->sub(new DateInterval('P1M'));
echo $d->format('Y-m-d') . "\n"; // Mar 2 (Feb 31 -> Mar 2)

// crossing year boundary
$d = new DateTime('2024-12-15');
$d->add(new DateInterval('P1M'));
echo $d->format('Y-m-d') . "\n"; // 2025-01-15

// year arithmetic
$d = new DateTime('2024-02-29');
$d->add(new DateInterval('P1Y'));
echo $d->format('Y-m-d') . "\n"; // 2025-03-01 (Feb 29 -> Mar 1 in non-leap)

// time-only interval
$d = new DateTime('2024-06-15 10:00:00');
$d->add(new DateInterval('PT2H30M'));
echo $d->format('Y-m-d H:i:s') . "\n";

// 12-hour formatting (h with leading zero was missing)
$d = new DateTime('2024-03-15 14:30:45');
echo $d->format('h:i:s A') . "\n";
echo $d->format('Y-m-d g:i:s a') . "\n";

// RFC 7231 / 2822 parsing (UTC and GMT are 0 offset, so display matches)
$d = new DateTime('Mon, 15 Jan 2024 10:30:00 GMT');
echo $d->format('Y-m-d H:i:s') . "\n";

$d = new DateTime('15 Jan 2024 10:30:00 UTC');
echo $d->format('Y-m-d H:i:s') . "\n";
