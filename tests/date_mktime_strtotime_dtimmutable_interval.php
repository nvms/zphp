<?php
date_default_timezone_set("UTC");

echo date("Y-m-d", 1700000000), "\n";
echo date("H:i:s", 1700000000), "\n";
echo date("Y-m-d H:i:s", 0), "\n";
echo date("Y", 1577836800), "\n";

echo date("D", 1700000000), "\n";
echo date("l", 1700000000), "\n";

echo date("N", 1700000000), "\n";
echo date("w", 1700000000), "\n";

echo date("z", mktime(0,0,0,1,1,2025)), "\n";
echo date("z", mktime(0,0,0,12,31,2025)), "\n";

echo date("W", mktime(0,0,0,1,1,2025)), "\n";
echo date("W", mktime(0,0,0,12,31,2025)), "\n";

echo date("U", mktime(0,0,0,1,1,2025)), "\n";

echo date("y", mktime(0,0,0,1,1,2025)), "\n";
echo date("L", mktime(0,0,0,1,1,2024)), "\n";
echo date("L", mktime(0,0,0,1,1,2025)), "\n";

echo date("t", mktime(0,0,0,2,1,2024)), "\n";
echo date("t", mktime(0,0,0,2,1,2025)), "\n";
echo date("t", mktime(0,0,0,4,1,2025)), "\n";

echo mktime(0,0,0,1,1,2025), "\n";
echo mktime(0,0,0,1,1,1970), "\n";
echo mktime(12,30,45,6,15,2025), "\n";

echo mktime(0,0,0,13,1,2024), "\n";

echo mktime(0,0,0,2,30,2025), "\n";

echo mktime(0,0,0,1,0,2025), "\n";

echo strtotime("2025-01-01"), "\n";
echo strtotime("2025-01-01 12:00:00"), "\n";
echo strtotime("2025-01-01 12:00:00 UTC"), "\n";

echo strtotime("now", 1700000000) > 0 ? "y" : "n", "\n";

echo strtotime("+1 day", 1700000000), "\n";
echo strtotime("-1 day", 1700000000), "\n";
echo strtotime("+1 week", 1700000000), "\n";
echo strtotime("+1 month", 1700000000), "\n";
echo strtotime("+1 year", 1700000000), "\n";

echo strtotime("2025-12-31 23:59:59"), "\n";

echo strtotime("invalid date") === false ? "false" : "valid", "\n";
echo strtotime("") === false ? "false" : "valid", "\n";

$d = new DateTimeImmutable("2025-01-15 12:00:00", new DateTimeZone("UTC"));
$d2 = $d->add(new DateInterval("P1D"));
echo $d->format("Y-m-d"), "\n";
echo $d2->format("Y-m-d"), "\n";
echo $d === $d2 ? "same" : "diff", "\n";

$d = new DateTimeImmutable("2025-01-15", new DateTimeZone("UTC"));
$d2 = $d->modify("+1 month");
echo $d->format("Y-m-d"), " -> ", $d2->format("Y-m-d"), "\n";

$d = new DateTimeImmutable("2025-01-15", new DateTimeZone("UTC"));
$d2 = $d->sub(new DateInterval("P7D"));
echo $d2->format("Y-m-d"), "\n";

$i = new DateInterval("P1Y2M3D");
echo $i->format("%y-%m-%d"), "\n";
echo $i->format("%Y-%M-%D"), "\n";

$i = new DateInterval("PT4H30M");
echo $i->format("%h:%i"), "\n";
echo $i->format("%H:%I"), "\n";

$i = new DateInterval("P0Y");
echo $i->format("%y"), "\n";
echo $i->format("%Y"), "\n";

$i = new DateInterval("P10Y");
echo $i->format("%y years"), "\n";
echo $i->format("%Y years"), "\n";

$d1 = new DateTimeImmutable("2025-01-01", new DateTimeZone("UTC"));
$d2 = new DateTimeImmutable("2025-06-15", new DateTimeZone("UTC"));
$diff = $d1->diff($d2);
echo $diff->format("%y years %m months %d days"), "\n";
echo $diff->format("%a total days"), "\n";

$d1 = new DateTimeImmutable("2025-06-15", new DateTimeZone("UTC"));
$d2 = new DateTimeImmutable("2025-01-01", new DateTimeZone("UTC"));
$diff = $d1->diff($d2);
echo $diff->format("%R%y-%m-%d"), "\n";

echo date("Y-m-d", strtotime("2024-02-29")), "\n";

echo date("F j, Y, g:i a", mktime(12,30,0,5,1,2025)), "\n";
echo date("M j, Y", mktime(0,0,0,12,25,2024)), "\n";

echo strtotime("midnight") > 0 ? "y" : "n", "\n";
echo strtotime("noon") > 0 ? "y" : "n", "\n";

$d = new DateTimeImmutable("2025-12-31 23:00:00", new DateTimeZone("UTC"));
$d2 = $d->modify("+2 hours");
echo $d2->format("Y-m-d H:i"), "\n";

echo date("z", mktime(0,0,0,3,1,2024)), "\n";
echo date("z", mktime(0,0,0,3,1,2025)), "\n";

$d = new DateTime("2025-01-15", new DateTimeZone("UTC"));
$ts = $d->getTimestamp();
echo $ts, "\n";
echo date("Y-m-d", $ts), "\n";

echo gmdate("Y-m-d H:i:s", 1700000000), "\n";
echo gmdate("Y-m-d", 0), "\n";

echo date_diff(
    new DateTime("2025-01-01", new DateTimeZone("UTC")),
    new DateTime("2026-03-15", new DateTimeZone("UTC"))
)->format("%y/%m/%d"), "\n";

echo date_format(new DateTime("2025-06-15 10:30:00", new DateTimeZone("UTC")), "Y-m-d H:i:s"), "\n";

echo (new DateTime("2025-01-01", new DateTimeZone("UTC")))->getTimestamp(), "\n";

echo checkdate(2, 29, 2024) ? "y" : "n", "\n";
echo checkdate(2, 29, 2025) ? "y" : "n", "\n";
echo checkdate(4, 31, 2025) ? "y" : "n", "\n";
echo checkdate(1, 1, 1900) ? "y" : "n", "\n";
echo checkdate(13, 1, 2025) ? "y" : "n", "\n";

echo date_default_timezone_get(), "\n";
