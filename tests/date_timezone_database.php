<?php
// zones come from php's bundled database: transitions, locations, legacy ids,
// abbreviations, and the identifier groups

foreach (["Europe/London", "America/New_York", "Australia/Sydney", "Asia/Kolkata"] as $id) {
    $tz = new DateTimeZone($id);
    echo $id, "\n";
    foreach ($tz->getTransitions(1577836800, 1735689600) as $t) {
        echo "  ", $t["ts"], " ", $t["time"], " ", $t["offset"], " ", $t["isdst"] ? "dst" : "std", " ", $t["abbr"], "\n";
    }
    $loc = $tz->getLocation();
    echo "  ", $loc["country_code"], " ", round($loc["latitude"], 2), " ", round($loc["longitude"], 2), "\n";
}

// the first entry of an unbounded list starts at PHP_INT_MIN
$all = (new DateTimeZone("Europe/Paris"))->getTransitions();
echo $all[0]["ts"] === PHP_INT_MIN ? "starts at min" : "starts elsewhere", "\n";
var_dump((new DateTimeZone("+05:00"))->getTransitions(), (new DateTimeZone("EST"))->getLocation());
var_dump(timezone_transitions_get(new DateTimeZone("Europe/Berlin"), 1700000000, 1720000000));

// legacy names resolve without the host's zoneinfo
foreach (["Asia/Calcutta", "US/Eastern", "america/new_york", "Europe/Kiev"] as $id) {
    $d = new DateTime("2021-07-01 12:00", new DateTimeZone($id));
    echo $id, " ", $d->format("c T e"), "\n";
}

var_dump(in_array("Europe/Kyiv", timezone_identifiers_list()));
var_dump(in_array("US/Eastern", timezone_identifiers_list()));
var_dump(in_array("US/Eastern", timezone_identifiers_list(DateTimeZone::ALL_WITH_BC)));
print_r(DateTimeZone::listIdentifiers(DateTimeZone::PER_COUNTRY, "NZ"));
print_r(timezone_identifiers_list(DateTimeZone::ANTARCTICA | DateTimeZone::ARCTIC));
try {
    timezone_identifiers_list(DateTimeZone::PER_COUNTRY);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}

$abbr = timezone_abbreviations_list();
echo count($abbr), " ", count($abbr["est"]), "\n";
print_r($abbr["acst"][0]);
var_dump($abbr["z"]);
var_dump(timezone_name_from_abbr("CET"), timezone_name_from_abbr("", 3600, 0), timezone_name_from_abbr("EST", -18000), timezone_name_from_abbr("bogus"), timezone_name_from_abbr("", 1234, 0), timezone_name_from_abbr("gmt"));
