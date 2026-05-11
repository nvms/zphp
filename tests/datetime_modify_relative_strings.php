<?php
$tz = new DateTimeZone("UTC");

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("+1 day");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("-3 days");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("+1 month");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-31 12:00:00", $tz);
$d->modify("+1 month");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("+1 year");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("+2 weeks");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("+1 hour");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("+30 minutes");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("+45 seconds");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("first day of this month");
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("last day of this month");
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("first day of next month");
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("last day of next month");
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("first day of last month");
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-02-15 12:00:00", $tz);
$d->modify("last day of february 2025");
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2024-02-15 12:00:00", $tz);
$d->modify("last day of february");
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("monday next week");
echo $d->format("Y-m-d D"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("midnight");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("noon");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("tomorrow");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("yesterday");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("+1 day +1 hour");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-31 23:00:00", $tz);
$d->modify("+1 hour");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-01 00:00:00", $tz);
$d->modify("-1 day");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-12-31 23:59:00", $tz);
$d->modify("+1 minute");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-03-15 12:00:00", $tz);
$d->modify("+6 months");
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("+0 day");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-01-15 12:00:00", $tz);
$d->modify("+1 second")->modify("+1 minute")->modify("+1 hour");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-03-01 00:00:00", $tz);
$d->modify("-1 second");
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2024-02-29 12:00:00", $tz);
$d->modify("+1 year");
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-06-15 14:30:00", $tz);
$d->setTime(0, 0, 0);
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTime("2025-06-15 14:30:00", $tz);
$d->setDate(2026, 1, 1);
echo $d->format("Y-m-d H:i:s"), "\n";

$d = new DateTimeImmutable("2025-01-15 12:00:00", $tz);
$next = $d->modify("+1 day");
echo $d->format("Y-m-d H:i:s"), " ", $next->format("Y-m-d H:i:s"), "\n";
echo $d === $next ? "same" : "diff", "\n";

$d = new DateTime("2025-01-15", $tz);
$d->add(new DateInterval("P1D"));
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-01-15", $tz);
$d->sub(new DateInterval("P1D"));
echo $d->format("Y-m-d"), "\n";

echo (new DateTime("2025-01-01", $tz))->getTimestamp(), "\n";
echo (new DateTime("2025-01-01 00:00:00", $tz))->getTimestamp(), "\n";

$d = new DateTime("2025-01-15T12:00:00+00:00", $tz);
echo $d->format("c"), "\n";

$d = new DateTime("now", $tz);
$d->modify("+0 seconds");
echo is_int($d->getTimestamp()) ? "y" : "n", "\n";
