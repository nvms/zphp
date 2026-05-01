<?php

// DatePeriod with start/interval/end
$start = new DateTime('2024-01-01');
$end = new DateTime('2024-01-05');
$interval = new DateInterval('P1D');
$period = new DatePeriod($start, $interval, $end);
foreach ($period as $d) echo $d->format('Y-m-d') . " ";
echo "\n";

// DatePeriod with recurrences (count) - uses DateTime args
$p2 = new DatePeriod(new DateTime('2024-06-01'), new DateInterval('P1W'), 3);
foreach ($p2 as $i => $d) echo $i . ":" . $d->format('Y-m-d') . " ";
echo "\n";

// DatePeriod EXCLUDE_START_DATE
$p3 = new DatePeriod(new DateTime('2024-01-01'), new DateInterval('P1D'), new DateTime('2024-01-04'), DatePeriod::EXCLUDE_START_DATE);
foreach ($p3 as $d) echo $d->format('m-d') . " ";
echo "\n";

// getStartDate / getEndDate / getDateInterval
$p4 = new DatePeriod($start, $interval, $end);
echo $p4->getStartDate()->format('Y-m-d') . "\n";
echo $p4->getEndDate()->format('Y-m-d') . "\n";
echo $p4->getDateInterval()->d . "\n";

// DateTime with H:i (no seconds) and timezone
$d = new DateTime('2024-06-01 12:00', new DateTimeZone('UTC'));
echo $d->format('Y-m-d H:i T') . "\n";
