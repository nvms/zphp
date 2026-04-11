<?php

// default timezone
echo date_default_timezone_get() . "\n";

// set and get
date_default_timezone_set("America/New_York");
echo date_default_timezone_get() . "\n";

// fixed timestamp for deterministic output
$ts = 1704067200; // 2024-01-01 00:00:00 UTC

// UTC formatting
date_default_timezone_set("UTC");
echo date("Y-m-d H:i:s T P O Z", $ts) . "\n";

// EST (winter, no DST)
date_default_timezone_set("America/New_York");
echo date("Y-m-d H:i:s T P", $ts) . "\n";

// JST (no DST ever)
date_default_timezone_set("Asia/Tokyo");
echo date("Y-m-d H:i:s T P", $ts) . "\n";

// CET (winter)
date_default_timezone_set("Europe/Paris");
echo date("Y-m-d H:i:s T P", $ts) . "\n";

// IST (+5:30, half-hour offset)
date_default_timezone_set("Asia/Kolkata");
echo date("Y-m-d H:i:s T P", $ts) . "\n";

// summer timestamp for DST testing
$summer_ts = 1721001600; // 2024-07-15 00:00:00 UTC

// EDT (summer DST)
date_default_timezone_set("America/New_York");
echo date("Y-m-d H:i:s T P", $summer_ts) . "\n";

// CEST (summer DST)
date_default_timezone_set("Europe/Paris");
echo date("Y-m-d H:i:s T P", $summer_ts) . "\n";

// mktime in local timezone
date_default_timezone_set("America/New_York");
$local_ts = mktime(12, 0, 0, 1, 15, 2024);
echo date("Y-m-d H:i:s T", $local_ts) . "\n";

// DateTimeZone
$tz = new DateTimeZone("America/New_York");
echo $tz->getName() . "\n";

$dt_utc = new DateTime("2024-01-01 00:00:00", new DateTimeZone("UTC"));
$offset = $tz->getOffset($dt_utc);
echo "offset: $offset\n";

// DateTime with timezone
$dt = new DateTime("2024-01-01 12:00:00", new DateTimeZone("America/New_York"));
echo $dt->format("Y-m-d H:i:s T") . "\n";
echo "ts: " . $dt->getTimestamp() . "\n";

// setTimezone
date_default_timezone_set("UTC");
$dt2 = new DateTime("2024-01-01 12:00:00", new DateTimeZone("UTC"));
$dt2->setTimezone(new DateTimeZone("America/New_York"));
echo $dt2->format("Y-m-d H:i:s T") . "\n";

// getTimezone
$tz2 = $dt2->getTimezone();
echo $tz2->getName() . "\n";

// invalid timezone returns false
$r = @date_default_timezone_set("Invalid/Zone");
echo ($r ? "true" : "false") . "\n";

// ISO 8601 format with timezone
date_default_timezone_set("America/New_York");
echo date("c", $ts) . "\n";

echo "done\n";
