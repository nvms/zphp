<?php
// regression: DateTimeZone::listIdentifiers() returns the full IANA zone list
// (419 entries) matching PHP 8.4's tzdb snapshot. previously zphp returned ~57
// representative zones which broke any code that whitelists a zone by checking
// membership in the list
$all = DateTimeZone::listIdentifiers();
echo count($all) . "\n";
// spot-check a handful of zones from each region
foreach (['Africa/Abidjan', 'America/St_Johns', 'Antarctica/Troll', 'Arctic/Longyearbyen',
          'Asia/Kathmandu', 'Atlantic/St_Helena', 'Australia/Lord_Howe',
          'Europe/Kyiv', 'Indian/Reunion', 'Pacific/Marquesas', 'UTC'] as $z) {
    echo (in_array($z, $all, true) ? 'y' : 'n') . " $z\n";
}
// timezone_identifiers_list is the procedural alias
echo (count(timezone_identifiers_list()) === count($all) ? 'y' : 'n') . " alias\n";
