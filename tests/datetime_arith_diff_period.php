<?php
$d = new DateTime("2025-01-15 12:00:00", new DateTimeZone("UTC"));
$d->add(new DateInterval("P1D"));
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", new DateTimeZone("UTC"));
$d->sub(new DateInterval("P1D"));
echo $d->format("Y-m-d H:i:s"), "\n";

$i = new DateInterval("P1D");
$i->invert = 1;
$d = new DateTime("2025-01-15 12:00:00", new DateTimeZone("UTC"));
$d->add($i);
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", new DateTimeZone("UTC"));
$d->sub($i);
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-31", new DateTimeZone("UTC"));
$d->add(new DateInterval("P1M"));
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-03-31", new DateTimeZone("UTC"));
$d->add(new DateInterval("P1M"));
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-01-15", new DateTimeZone("UTC"));
$d->modify("+1 day");
$d->modify("+1 hour");
$d->modify("+30 minutes");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 23:30", new DateTimeZone("UTC"));
$d->modify("+1 hour");
echo $d->format("Y-m-d H:i:s"), "\n";

$d1 = new DateTime("2025-01-01", new DateTimeZone("UTC"));
$d2 = new DateTime("2025-12-31", new DateTimeZone("UTC"));
$di = $d1->diff($d2);
echo $di->y, " ", $di->m, " ", $di->d, " days=", $di->days, " inv=", $di->invert, "\n";

$d1 = new DateTime("2025-12-31", new DateTimeZone("UTC"));
$d2 = new DateTime("2025-01-01", new DateTimeZone("UTC"));
$di = $d1->diff($d2);
echo $di->y, " ", $di->m, " ", $di->d, " days=", $di->days, " inv=", $di->invert, "\n";

$d1 = new DateTime("2024-01-01", new DateTimeZone("UTC"));
$d2 = new DateTime("2025-01-01", new DateTimeZone("UTC"));
$di = $d1->diff($d2);
echo $di->y, " ", $di->m, " ", $di->d, " days=", $di->days, "\n";

$d1 = new DateTime("2025-01-15 10:00:00", new DateTimeZone("UTC"));
$d2 = new DateTime("2025-01-16 09:00:00", new DateTimeZone("UTC"));
$di = $d1->diff($d2);
echo $di->d, " ", $di->h, " ", $di->i, " ", $di->s, "\n";

$di = new DateInterval("P1Y2M3DT4H5M6S");
echo $di->format("%y-%m-%d %h:%i:%s"), "\n";
echo $di->format("%Y-%M-%D %H:%I:%S"), "\n";
echo $di->format("%R%y years"), "\n";

$di = new DateInterval("P2D");
$di->invert = 1;
echo $di->format("%R%d"), "\n";
echo $di->format("%r%d"), "\n";

$d1 = new DateTime("2025-01-01", new DateTimeZone("UTC"));
$d2 = new DateTime("2025-01-10", new DateTimeZone("UTC"));
$di = $d1->diff($d2);
echo $di->format("%a"), "\n";

$start = new DateTime("2025-01-01", new DateTimeZone("UTC"));
$end = new DateTime("2025-01-04", new DateTimeZone("UTC"));
$interval = new DateInterval("P1D");
$period = new DatePeriod($start, $interval, $end);
foreach ($period as $d) echo $d->format("Y-m-d"), "\n";

$start = new DateTime("2025-01-01", new DateTimeZone("UTC"));
$interval = new DateInterval("P1D");
$period = new DatePeriod($start, $interval, 3);
foreach ($period as $d) echo $d->format("Y-m-d"), "\n";

$start = new DateTime("2025-01-01", new DateTimeZone("UTC"));
$end = new DateTime("2025-01-04", new DateTimeZone("UTC"));
$interval = new DateInterval("P1D");
$period = new DatePeriod($start, $interval, $end, DatePeriod::EXCLUDE_START_DATE);
foreach ($period as $d) echo $d->format("Y-m-d"), "\n";

$d = new DateTimeImmutable("2025-01-15", new DateTimeZone("UTC"));
$d2 = $d->add(new DateInterval("P1D"));
echo $d->format("Y-m-d"), " -> ", $d2->format("Y-m-d"), "\n";

$d = new DateTimeImmutable("2025-01-15 23:00", new DateTimeZone("UTC"));
$d2 = $d->modify("+2 hours");
echo $d->format("Y-m-d H:i"), " -> ", $d2->format("Y-m-d H:i"), "\n";
