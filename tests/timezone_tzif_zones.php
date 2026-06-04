<?php

// zones NOT in zphp's hardcoded table are resolved by parsing the system tzdb
// (TZif) binary, so any IANA zone gets the correct offset/DST/abbrev instead of
// throwing "Unknown or bad timezone". the cases below have decades-stable rules
// so they don't depend on the installed tzdata version. (the compat harness
// diffs zphp against the local php at runtime, both reading the same tzdb.)

$cases = [
    ['Pacific/Chatham',     '2024-01-15 12:00:00'], // +13:45 (Chatham DST, summer)
    ['Pacific/Chatham',     '2024-07-15 12:00:00'], // +12:45 (std, winter)
    ['Asia/Kathmandu',      '2024-06-15 12:00:00'], // +05:45 (no DST, fixed)
    ['Pacific/Honolulu',    '2024-06-15 12:00:00'], // -10:00 (no DST)
    ['Africa/Johannesburg', '2024-06-15 12:00:00'], // +02:00 (no DST)
    ['Asia/Kolkata',        '2024-06-15 12:00:00'], // +05:30 (no DST)
    ['Pacific/Marquesas',   '2024-06-15 12:00:00'], // -09:30 (rare half-hour offset)
];

foreach ($cases as [$zone, $when]) {
    $d = new DateTime($when, new DateTimeZone($zone));
    echo str_pad($zone, 22), $d->format('P'), ' offset=', $d->getOffset(), "\n";
}

// an unknown zone still throws like PHP
try {
    new DateTimeZone('Not/AZone');
    echo "no-throw\n";
} catch (\Exception $e) {
    echo "unknown throws: ", get_class($e), "\n";
}
