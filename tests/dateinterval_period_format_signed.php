<?php
$i = new DateInterval("P1Y2M3DT4H5M6S");
echo $i->y, "-", $i->m, "-", $i->d, " ", $i->h, ":", $i->i, ":", $i->s, "\n";
echo $i->format("%Y-%M-%D %H:%I:%S"), "\n";
echo $i->format("%y-%m-%d %h:%i:%s"), "\n";
echo $i->format("%R"), "\n";
echo $i->format("%r"), "\n";

$i2 = DateInterval::createFromDateString("1 year 2 months 3 days");
echo $i2->y, " ", $i2->m, " ", $i2->d, "\n";

$i3 = DateInterval::createFromDateString("2 weeks");
echo $i3->d, "\n";

$i4 = DateInterval::createFromDateString("-3 days");
echo $i4->d, "\n";
echo $i4->format("%r%d"), "\n";
echo $i4->format("%d"), "\n";

$a = new DateTime("2024-01-01");
$b = new DateTime("2025-03-15");
$diff = $a->diff($b);
echo $diff->y, "-", $diff->m, "-", $diff->d, "\n";
echo $diff->days, "\n";

$a = new DateTime("2024-01-15");
$b = new DateTime("2024-01-10");
$diff = $a->diff($b);
echo $diff->invert, " ", $diff->d, "\n";

$a = new DateTime("2024-01-15 10:00:00");
$b = new DateTime("2024-01-15 14:30:45");
$diff = $a->diff($b);
echo $diff->h, ":", $diff->i, ":", $diff->s, "\n";

$a = new DateTime("2024-01-01");
$a->add(new DateInterval("P1Y"));
echo $a->format("Y-m-d"), "\n";

$a = new DateTime("2024-01-01");
$a->sub(new DateInterval("P1M"));
echo $a->format("Y-m-d"), "\n";

$start = new DateTime("2024-01-01");
$end = new DateTime("2024-01-05");
$interval = new DateInterval("P1D");
$period = new DatePeriod($start, $interval, $end);
foreach ($period as $d) echo $d->format("Y-m-d"), " ";
echo "\n";

$period2 = new DatePeriod($start, $interval, 3);
foreach ($period2 as $d) echo $d->format("Y-m-d"), " ";
echo "\n";

$count = 0;
$start = new DateTime("2024-01-01");
$end = new DateTime("2024-01-15");
$interval = new DateInterval("P3D");
foreach (new DatePeriod($start, $interval, $end) as $d) $count++;
echo $count, "\n";

$i5 = new DateInterval("P0Y0M5D");
echo $i5->y, $i5->m, $i5->d, "\n";

$i6 = new DateInterval("PT2H30M");
echo $i6->h, ":", $i6->i, "\n";

$i7 = new DateInterval("P1W");
echo $i7->d, "\n";

$ymd = $diff->format("%a days");
echo $ymd, "\n";

$d = new DateTime("2024-01-01");
$d->add(new DateInterval("PT45M"));
echo $d->format("H:i"), "\n";

$d = new DateTime("2024-12-31 23:59:30");
$d->add(new DateInterval("PT45S"));
echo $d->format("Y-m-d H:i:s"), "\n";

$start = new DateTime("2024-01-01");
$end = new DateTime("2024-01-04");
$it = new DatePeriod($start, new DateInterval("P1D"), $end);
$keys = [];
$vals = [];
foreach ($it as $k => $v) { $keys[] = $k; $vals[] = $v->format("Y-m-d"); }
echo implode(",", $keys), " ", implode(",", $vals), "\n";

$start = new DateTime("2024-01-01");
$it = new DatePeriod($start, new DateInterval("P1M"), 3);
$out = [];
foreach ($it as $d) $out[] = $d->format("Y-m-d");
echo implode(" ", $out), "\n";
