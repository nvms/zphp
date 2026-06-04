<?php

// southern-hemisphere DST is active in the SUMMER and wraps the calendar year
// (spring start through year-end, plus year-start through autumn end). zphp
// previously had no rule for it and returned standard time year-round for
// Australia/NZ. Australia eastern (NSW/VIC/TAS): 1st Sunday Oct -> 1st Sunday
// April. New Zealand: last Sunday Sept -> 1st Sunday April. northern-hemisphere
// US/EU zones must stay correct.

$cases = [
    // [zone, datetime, expected 'P T']
    ['Australia/Sydney',  '2024-01-15 12:00:00'],  // southern summer -> +11:00 AEDT
    ['Australia/Sydney',  '2024-07-15 12:00:00'],  // southern winter -> +10:00 AEST
    ['Australia/Sydney',  '2024-12-25 12:00:00'],  // summer (year-end) -> +11:00
    ['Australia/Melbourne', '2024-02-01 00:00:00'],// summer -> +11:00
    ['Australia/Hobart',  '2024-06-01 00:00:00'],  // winter -> +10:00
    ['Australia/Brisbane', '2024-01-15 12:00:00'], // no DST -> +10:00 year-round
    ['Australia/Perth',   '2024-01-15 12:00:00'],  // no DST -> +08:00
    ['Pacific/Auckland',  '2024-01-15 12:00:00'],  // summer -> +13:00 NZDT
    ['Pacific/Auckland',  '2024-07-15 12:00:00'],  // winter -> +12:00 NZST
    // northern hemisphere must stay correct
    ['America/New_York',  '2024-07-01 12:00:00'],  // EDT -> -04:00
    ['America/New_York',  '2024-01-01 12:00:00'],  // EST -> -05:00
    ['Europe/London',     '2024-07-01 12:00:00'],  // BST -> +01:00
    ['Europe/Paris',      '2024-01-01 12:00:00'],  // CET -> +01:00
    ['Asia/Tokyo',        '2024-07-01 12:00:00'],  // no DST -> +09:00
];

foreach ($cases as [$zone, $when]) {
    $d = new DateTime($when, new DateTimeZone($zone));
    echo str_pad($zone, 22), $when, '  ', $d->format('P'), ' offset=', $d->getOffset(), "\n";
}

// getOffset around a southern transition (Sydney 2024 DST starts 1st Sun Oct = Oct 6, 02:00 -> 03:00)
$pre  = new DateTime('2024-10-06 01:30:00', new DateTimeZone('Australia/Sydney'));
$post = new DateTime('2024-10-06 03:30:00', new DateTimeZone('Australia/Sydney'));
echo "syd pre-transition: ",  $pre->format('P'),  "\n";  // +10:00
echo "syd post-transition: ", $post->format('P'), "\n";  // +11:00
