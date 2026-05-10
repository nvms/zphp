<?php
date_default_timezone_set("UTC");

// DateTime add interval
$d = new DateTime("2025-01-15 10:00:00");
$d->add(new DateInterval("P1D"));
echo $d->format("Y-m-d H:i:s"), "\n"; // 2025-01-16 10:00:00

$d = new DateTime("2025-01-15 10:00:00");
$d->add(new DateInterval("P1M"));
echo $d->format("Y-m-d H:i:s"), "\n"; // 2025-02-15 10:00:00

$d = new DateTime("2025-01-15 10:00:00");
$d->add(new DateInterval("P1Y2M3D"));
echo $d->format("Y-m-d H:i:s"), "\n"; // 2026-03-18 10:00:00

$d = new DateTime("2025-01-15 10:00:00");
$d->add(new DateInterval("PT2H30M15S"));
echo $d->format("Y-m-d H:i:s"), "\n"; // 2025-01-15 12:30:15

$d = new DateTime("2025-01-15 10:00:00");
$d->add(new DateInterval("P1DT1H"));
echo $d->format("Y-m-d H:i:s"), "\n";

// sub
$d = new DateTime("2025-01-15 10:00:00");
$d->sub(new DateInterval("P1D"));
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-03-15 10:00:00");
$d->sub(new DateInterval("P1M"));
echo $d->format("Y-m-d H:i:s"), "\n"; // 2025-02-15

// month overflow
$d = new DateTime("2025-01-31");
$d->add(new DateInterval("P1M"));
echo $d->format("Y-m-d"), "\n"; // 2025-03-03 (PHP: month overflows)

$d = new DateTime("2025-01-30");
$d->add(new DateInterval("P1M"));
echo $d->format("Y-m-d"), "\n"; // 2025-03-02

// year leap
$d = new DateTime("2024-02-29");
$d->add(new DateInterval("P1Y"));
echo $d->format("Y-m-d"), "\n"; // 2025-03-01

// negative interval via invert
$i = new DateInterval("P5D");
$i->invert = 1;
$d = new DateTime("2025-01-15");
$d->add($i);
echo $d->format("Y-m-d"), "\n"; // 2025-01-10

// date_diff
$a = new DateTime("2025-01-15 10:00:00");
$b = new DateTime("2025-03-20 14:30:00");
$diff = $a->diff($b);
echo $diff->y, "y ", $diff->m, "m ", $diff->d, "d ", $diff->h, "h ", $diff->i, "i ", $diff->s, "s\n";
echo "invert=", $diff->invert, " days=", $diff->days, "\n";

$diff = $b->diff($a);
echo $diff->y, "y ", $diff->m, "m ", $diff->d, "d invert=", $diff->invert, "\n";

// date_diff DST boundaries (US/Eastern)
$tz = new DateTimeZone("America/New_York");
$a = new DateTime("2025-03-08 12:00:00", $tz);
$b = new DateTime("2025-03-10 12:00:00", $tz);
$diff = $a->diff($b);
echo $diff->d, "d ", $diff->h, "h\n"; // 2d 0h (date_diff is calendar-based)

// DateInterval format
$i = new DateInterval("P1Y2M3DT4H5M6S");
echo $i->format("%y-%m-%d %h:%i:%s"), "\n"; // 1-2-3 4:5:6
echo $i->format("%Y-%M-%D %H:%I:%S"), "\n"; // 01-02-03 04:05:06
echo $i->format("%R%y"), "\n"; // +1
$i->invert = 1;
echo $i->format("%R%y"), "\n"; // -1
echo $i->format("%a"), "\n"; // (unknown without ref)

// from diff: %a is days
$a = new DateTime("2025-01-01");
$b = new DateTime("2025-12-31");
$di = $a->diff($b);
echo $di->format("%a days"), "\n"; // 364 days

// modify
$d = new DateTime("2025-01-15");
$d->modify("+1 day");
echo $d->format("Y-m-d"), "\n";
$d->modify("+1 week");
echo $d->format("Y-m-d"), "\n";
$d->modify("-1 month");
echo $d->format("Y-m-d"), "\n";
$d->modify("next monday");
echo $d->format("Y-m-d D"), "\n";
$d = new DateTime("2025-01-15");
$d->modify("first day of next month");
echo $d->format("Y-m-d"), "\n"; // 2025-02-01
$d->modify("last day of this month");
echo $d->format("Y-m-d"), "\n"; // 2025-02-28
$d->modify("midnight");
echo $d->format("Y-m-d H:i:s"), "\n";

// modify chained
$d = new DateTime("2025-06-15 12:00:00");
$d->modify("+2 days +3 hours");
echo $d->format("Y-m-d H:i:s"), "\n";

// DateTimeImmutable returns new instance
$d1 = new DateTimeImmutable("2025-01-15");
$d2 = $d1->modify("+1 day");
echo $d1->format("Y-m-d"), " | ", $d2->format("Y-m-d"), "\n"; // d1 unchanged

$d3 = $d1->add(new DateInterval("P5D"));
echo $d1->format("Y-m-d"), " | ", $d3->format("Y-m-d"), "\n";

$d4 = $d1->setDate(2030, 6, 15);
echo $d1->format("Y-m-d"), " | ", $d4->format("Y-m-d"), "\n";

$d5 = $d1->setTime(15, 30, 45);
echo $d1->format("H:i:s"), " | ", $d5->format("H:i:s"), "\n";

// DateInterval createFromDateString
$i = DateInterval::createFromDateString("3 days 4 hours");
echo $i->d, "/", $i->h, "\n";

// date_create + date_add
$d = date_create("2025-01-15");
date_add($d, new DateInterval("P10D"));
echo date_format($d, "Y-m-d"), "\n";

// mutual sub then add round-trip
$d = new DateTime("2025-06-15 10:00:00");
$orig = $d->format("Y-m-d H:i:s");
$d->add(new DateInterval("P1Y2M3DT4H5M6S"));
$d->sub(new DateInterval("P1Y2M3DT4H5M6S"));
echo $d->format("Y-m-d H:i:s"), " == ", $orig, " ? ", $d->format("Y-m-d H:i:s") === $orig ? "yes" : "no", "\n";

// getTimestamp
$d = new DateTime("2025-01-15 12:00:00", new DateTimeZone("UTC"));
echo $d->getTimestamp(), "\n";

// from timestamp
$d = (new DateTime())->setTimestamp(1700000000);
$d->setTimezone(new DateTimeZone("UTC"));
echo $d->format("Y-m-d H:i:s"), "\n";

// equality / comparison
$a = new DateTime("2025-01-15");
$b = new DateTime("2025-01-15");
var_dump($a == $b);
var_dump($a === $b);
var_dump($a < new DateTime("2025-01-16"));
var_dump($a > new DateTime("2025-01-14"));
