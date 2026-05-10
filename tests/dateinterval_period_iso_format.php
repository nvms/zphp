<?php
$i = new DateInterval("P1Y2M3DT4H5M6S");
echo $i->format("%Y-%M-%D %H:%I:%S"), "\n";
echo $i->format("%y-%m-%d %h:%i:%s"), "\n";
echo $i->format("%R"), "\n";
echo $i->format("%r"), "\n";

$i = new DateInterval("P10D");
echo $i->format("%d days"), "\n";
echo $i->format("%D days"), "\n";

$i = new DateInterval("PT3M5S");
echo $i->format("%i:%s"), "\n";
echo $i->format("%I:%S"), "\n";

$i = new DateInterval("P0Y");
echo $i->format("%y-%m-%d"), "\n";

$d1 = new DateTime("2025-01-01");
$d2 = new DateTime("2025-12-31");
$i = $d1->diff($d2);
echo $i->format("%a"), "\n";
echo $i->format("%R%a"), "\n";
echo $i->format("%y y, %m m, %d d"), "\n";

$d1 = new DateTime("2025-12-31");
$d2 = new DateTime("2025-01-01");
$i = $d1->diff($d2);
echo $i->format("%R%a"), "\n";
echo $i->format("%r%a"), "\n";
echo $i->invert, "\n";

$d1 = new DateTimeImmutable("2025-01-01 10:30:45");
$d2 = new DateTimeImmutable("2025-01-02 11:32:50");
$i = $d1->diff($d2);
echo $i->format("%d %h %i %s"), "\n";

$i = new DateInterval("PT0S");
$i->invert = 0;
echo $i->format("%R"), "\n";
$i->invert = 1;
echo $i->format("%R"), "\n";

$start = new DateTime("2025-01-01");
$interval = new DateInterval("P1M");
$period = new DatePeriod($start, $interval, 3);
echo count(iterator_to_array($period)), "\n";

$start = new DateTime("2025-01-01");
$end = new DateTime("2025-05-01");
$interval = new DateInterval("P1M");
$period = new DatePeriod($start, $interval, $end);
foreach ($period as $d) echo $d->format("Y-m-d"), "\n";

$start = new DateTime("2025-01-01");
$end = new DateTime("2025-04-01");
$interval = new DateInterval("P1M");
$period = new DatePeriod($start, $interval, $end);
$n = 0;
foreach ($period as $d) $n++;
echo $n, "\n";

$start = new DateTime("2025-01-01");
$interval = new DateInterval("P1D");
$period = new DatePeriod($start, $interval, 5);
$result = [];
foreach ($period as $d) $result[] = $d->format("Y-m-d");
print_r($result);

$start = new DateTime("2025-01-01");
$interval = new DateInterval("P1D");
$period = new DatePeriod($start, $interval, 3, DatePeriod::EXCLUDE_START_DATE);
$out = [];
foreach ($period as $d) $out[] = $d->format("Y-m-d");
print_r($out);

$di = DateInterval::createFromDateString("1 day");
echo $di->d, "\n";
$di = DateInterval::createFromDateString("3 weeks");
echo $di->d, "\n";
$di = DateInterval::createFromDateString("2 months");
echo $di->m, "\n";
$di = DateInterval::createFromDateString("1 year 2 months 3 days");
echo $di->y, " ", $di->m, " ", $di->d, "\n";
$di = DateInterval::createFromDateString("4 hours 30 minutes");
echo $di->h, " ", $di->i, "\n";
$di = DateInterval::createFromDateString("-5 days");
echo $di->d, " ", $di->invert, "\n";

$i = new DateInterval("P1DT2H");
echo $i->y, " ", $i->m, " ", $i->d, " ", $i->h, " ", $i->i, " ", $i->s, " ", $i->invert, "\n";

$d1 = new DateTime("2025-06-15 14:30:00");
$d2 = new DateTime("2025-06-15 16:45:30");
$i = $d1->diff($d2);
echo $i->h, " ", $i->i, " ", $i->s, "\n";

$d1 = new DateTime("2024-02-29");
$d2 = new DateTime("2025-02-28");
$i = $d1->diff($d2);
echo $i->y, " ", $i->m, " ", $i->d, " a=", $i->days, "\n";

$d1 = new DateTime("2024-01-01");
$d2 = new DateTime("2024-12-31");
$i = $d1->diff($d2);
echo $i->days, "\n";

$di = new DateInterval("P1D");
$d = new DateTime("2025-06-15");
$d->add($di);
echo $d->format("Y-m-d"), "\n";
$d->add($di);
$d->add($di);
echo $d->format("Y-m-d"), "\n";
