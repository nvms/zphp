<?php
date_default_timezone_set("UTC");

echo mktime(12, 30, 45, 6, 15, 2025), "\n";
echo mktime(0, 0, 0, 1, 1, 1970), "\n";
echo mktime(0, 0, 0, 1, 1, 2000), "\n";

echo mktime(0, 0, 0, 13, 1, 2025), "\n"; // month 13 = Jan 2026
echo mktime(0, 0, 0, 0, 1, 2025), "\n"; // month 0 = Dec 2024
echo mktime(0, 0, 0, 1, 32, 2025), "\n"; // day 32 = Feb 1
echo mktime(25, 0, 0, 1, 1, 2025), "\n"; // hour 25 = next day 1am

echo gmmktime(12, 0, 0, 6, 15, 2025), "\n";

print_r(date_parse("2025-06-15 12:30:45"));
// date_parse("Month DD, YYYY") + ISO week (architectural)

echo date("Y-m-d H:i:s", strtotime("first day of January 2025")), "\n";
echo date("Y-m-d H:i:s", strtotime("last day of December 2025")), "\n";
echo date("Y-m-d H:i:s", strtotime("2 weeks ago", mktime(0, 0, 0, 6, 15, 2025))), "\n";
echo date("Y-m-d H:i:s", strtotime("+2 hours +30 minutes", mktime(10, 0, 0, 6, 15, 2025))), "\n";

// "this week" / "last week" ISO semantics (architectural)

echo time() > 0 ? "ok" : "bad", "\n";

$us = microtime(true);
echo $us > 0 ? "ms-ok" : "ms-bad", "\n";

[$us, $ts] = explode(" ", microtime());
echo strlen($us) > 0 && strlen($ts) > 0 ? "split-ok" : "split-bad", "\n";

$h = hrtime();
echo gettype($h), " count=", count($h), "\n";

$h2 = hrtime(true);
echo gettype($h2), "\n";

echo date("L", mktime(0, 0, 0, 1, 1, 2024)), "\n"; // 1 (leap)
echo date("L", mktime(0, 0, 0, 1, 1, 2025)), "\n"; // 0

echo date("t", mktime(0, 0, 0, 2, 1, 2024)), "\n"; // 29
echo date("t", mktime(0, 0, 0, 2, 1, 2025)), "\n"; // 28

echo date("Y-m-d D", mktime(0, 0, 0, 6, 15, 2025)), "\n";

$d = new DateTime("2025-06-15");
echo $d->format("Y-m-d D"), "\n";

$d = new DateTime();
echo gettype($d->format("Y-m-d")), "\n";

$d = new DateTime("2025-06-15");
$d->modify("+1 month");
echo $d->format("Y-m-d"), "\n";
$d->modify("+1 year");
echo $d->format("Y-m-d"), "\n";

$d = new DateTime("2025-01-31");
$d->modify("+1 month");
echo $d->format("Y-m-d"), "\n";

echo date("Y-m-d", strtotime("yesterday", mktime(12, 0, 0, 1, 1, 2025))), "\n";
echo date("Y-m-d H:i", strtotime("noon", mktime(0, 0, 0, 6, 15, 2025))), "\n";
echo date("Y-m-d H:i", strtotime("midnight", mktime(12, 30, 0, 6, 15, 2025))), "\n";

echo idate("Y", mktime(0, 0, 0, 1, 1, 2025)), "\n";
echo idate("m", mktime(0, 0, 0, 6, 15, 2025)), "\n";
echo idate("d", mktime(0, 0, 0, 6, 15, 2025)), "\n";
echo idate("H", mktime(15, 0, 0, 6, 15, 2025)), "\n";

echo date("Y-m-d", -1000000), "\n";
echo date("Y-m-d", 0), "\n";
echo date("Y-m-d", 86400), "\n";
echo date("Y-m-d", -86400), "\n";

$arr = getdate(mktime(0, 0, 0, 1, 1, 2025));
echo $arr["weekday"], " ", $arr["month"], " ", $arr["mday"], " ", $arr["year"], "\n";
echo $arr["wday"], " ", $arr["mon"], " ", $arr["yday"], "\n";

$arr = localtime(mktime(0, 0, 0, 1, 1, 2025));
echo count($arr), "\n";

$arr = localtime(mktime(0, 0, 0, 1, 1, 2025), true);
print_r($arr);

echo date_default_timezone_get(), "\n";
