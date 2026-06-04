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
    // Egypt's DST is irregular (not a Sunday rule) so it resolves via TZif:
    // wrong-every-summer (+02 not +03) under the old hardcoded .none entry
    ['Africa/Cairo',        '2024-01-15 12:00:00'], // +02:00 (winter)
    ['Africa/Cairo',        '2024-07-15 12:00:00'], // +03:00 (summer DST)
];

foreach ($cases as [$zone, $when]) {
    $d = new DateTime($when, new DateTimeZone($zone));
    echo str_pad($zone, 22), $d->format('P'), ' offset=', $d->getOffset(), "\n";
}

// modern-tzdb numeric abbreviations for zones that dropped DST (these were
// "BRT" / "IRST" letter codes in the table; PHP/tzdb now use numeric)
echo 'Sao_Paulo T: ', (new DateTime('2024-06-15', new DateTimeZone('America/Sao_Paulo')))->format('T'), "\n"; // -03
echo 'Tehran T: ',    (new DateTime('2024-06-15', new DateTimeZone('Asia/Tehran')))->format('T'), "\n";       // +0330
echo 'Cairo T: ',     (new DateTime('2024-07-15', new DateTimeZone('Africa/Cairo')))->format('T'), "\n";      // EEST
// more table zones whose tzdb abbrev is numeric (were ART/TRT/SGT/GST/ICT/BST/NPT)
foreach (['Asia/Singapore'=>'+08','Asia/Bangkok'=>'+07','Asia/Dhaka'=>'+06','Asia/Dubai'=>'+04',
          'Asia/Kathmandu'=>'+0545','Europe/Istanbul'=>'+03','America/Argentina/Buenos_Aires'=>'-03'] as $z=>$exp) {
    echo "$z T: ", (new DateTime('2024-06-15', new DateTimeZone($z)))->format('T'), "\n";
}

// an unknown zone still throws like PHP
try {
    new DateTimeZone('Not/AZone');
    echo "no-throw\n";
} catch (\Exception $e) {
    echo "unknown throws: ", get_class($e), "\n";
}
