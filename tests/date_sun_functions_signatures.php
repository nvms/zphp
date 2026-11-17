<?php
// natives whose signatures zphp lacked: missing arguments are an
// ArgumentCountError, named ones land on their parameters
foreach (['date_sunrise', 'date_sunset', 'date_sun_info', 'show_source', 'timezone_name_from_abbr'] as $f) {
    try {
        @$f();
    } catch (ArgumentCountError $e) {
        echo $e->getMessage(), "\n";
    }
}
var_dump(@date_sunrise(timestamp: 0, returnFormat: SUNFUNCS_RET_TIMESTAMP, latitude: 38.4, longitude: -9, zenith: 90, utcOffset: 0));
var_dump(timezone_name_from_abbr("EST"), timezone_name_from_abbr(abbr: "", utcOffset: 3600, isDST: 0));
var_dump(count(date_sun_info(latitude: 31.7667, longitude: 35.2333, timestamp: 0)));
foreach (['date_sunrise', 'date_sun_info', 'timezone_name_from_abbr'] as $f) {
    $params = array_map(fn($p) => (string) $p, (new ReflectionFunction($f))->getParameters());
    echo implode("\n", $params), "\n";
}
