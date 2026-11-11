<?php
// date_sun_info(), date_sunrise() and date_sunset(): timelib's astro.c

foreach (["UTC", "Europe/Oslo", "America/New_York", "Asia/Kolkata", "Australia/Adelaide"] as $zone) {
    date_default_timezone_set($zone);
    foreach ([[1165881600, 31.7667, 35.2333], [1176422400, 52.37, 4.89], [1421020800, 69.68, 18.94], [1435708800, 78.22, 15.65], [1700000000, -33.87, 151.21], [1700000000, 0, 0]] as [$ts, $lat, $lon]) {
        echo $zone, " ", $ts, " ", $lat, " ", $lon, "\n";
        foreach (date_sun_info($ts, $lat, $lon) as $k => $v) {
            echo "  ", $k, " ", is_bool($v) ? var_export($v, true) : date("Y-m-d H:i:s T", $v), "\n";
        }
        foreach ([SUNFUNCS_RET_TIMESTAMP, SUNFUNCS_RET_STRING, SUNFUNCS_RET_DOUBLE] as $f) {
            echo "  ", var_export(@date_sunrise($ts, $f, $lat, $lon), true), " ", var_export(@date_sunset($ts, $f, $lat, $lon, 90.83, 2.5), true), "\n";
        }
    }
}
var_dump(@date_sunrise(0), @date_sunset(0, SUNFUNCS_RET_DOUBLE));
foreach ([[NAN, 0], [0, INF]] as [$lat, $lon]) {
    try {
        date_sun_info(0, $lat, $lon);
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
    var_dump(@date_sunset(0, SUNFUNCS_RET_STRING, $lat, $lon));
}
try {
    @date_sunrise(0, 7);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(ini_get("date.default_latitude"), ini_get("date.sunset_zenith"));
