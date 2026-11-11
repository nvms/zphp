<?php
// microtime() prints its fraction with eight digits; gettimeofday() gives
// the default zone's offset in minutes west of utc

var_dump(preg_match('/^0\.\d{8} \d+$/', microtime()));
var_dump(is_float(microtime(true)), is_float(gettimeofday(true)));
foreach (["UTC", "Asia/Kolkata", "America/New_York", "Australia/Lord_Howe"] as $zone) {
    date_default_timezone_set($zone);
    $t = gettimeofday();
    var_dump(array_keys($t), $t["minuteswest"] === -(int) date("Z", $t["sec"]) / 60, $t["dsttime"] === (int) date("I", $t["sec"]), $t["usec"] >= 0 && $t["usec"] < 1000000);
}
try {
    gettimeofday([]);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
