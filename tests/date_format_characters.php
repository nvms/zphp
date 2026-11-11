<?php
// date_format() as php_date.c has it: zone characters per zone kind, gmdate's
// utc, year padding and signs, and the default zone read as a zone id

$ts = 1593561600; // 2020-07-01 00:00:00 utc
foreach (["UTC", "Europe/Paris", "+05:30", "-03:15", "EST", "CEST", "Z"] as $zone) {
    $d = new DateTime("@$ts");
    $d->setTimezone(new DateTimeZone($zone));
    echo str_pad($zone, 14), $d->format("e|T|I|O|P|p|Z|c|r|U"), "\n";
}
echo gmdate("e|T|I|O|P|p|Z|c|r|U|B", $ts), "\n";
echo gmdate("D, d M Y H:i:s T", 1001894400), "\n";
echo gmdate(DATE_COOKIE, 1218182888), "\n";

foreach ([-100000000000, -62135596800, -1, 0, 253402300800, 300000000000] as $t) {
    echo $t, ": ", gmdate("Y|y|x|X|o|W|N|w|z|t|L|S|jS|D|l|M|F|g|G|h|H|a|A", $t), "\n";
}
echo gmdate("u v"), "\n";
var_dump(gmdate("Y\\"));

// a default zone whose name is also an abbreviation is the zone id, with dst
foreach (["CET", "EET", "EST5EDT", "MST", "Asia/Calcutta"] as $zone) {
    date_default_timezone_set($zone);
    echo $zone, ": ", date("T I O e", $ts), " ", date("T I O", $ts + 180 * 86400), "\n";
    $d = new DateTime("2020-07-01 12:00");
    echo "  ", $d->format("T I O e"), " ", json_encode($d), "\n";
    echo "  ", mktime(12, 0, 0, 7, 1, 2020), " ", idate("I", $ts), " ", localtime($ts, true)["tm_isdst"], "\n";
}

date_default_timezone_set("America/New_York");
foreach ([0, 69, 70, 99, 100, 101, 1969, -1] as $y) {
    echo $y, " => ", date("Y-m-d H:i:s T", mktime(1, 2, 3, 4, 5, $y)), "\n";
}
echo date("c", mktime(25, 70, 70, 14, 35, 2020)), "\n";
echo date("c", gmmktime(0, 0, 0, 1, 1, 2020)), "\n";
print_r(getdate(1700000000));
print_r(localtime(1700000000));
foreach (str_split("dhHimstwyYzIULNoWBZgGjn") as $c) echo $c, "=", idate($c, 1700000000), " ";
echo "\n";
var_dump(idate("x", 0), idate("YY", 0), idate("y", mktime(0, 0, 0, 1, 1, -1)));
