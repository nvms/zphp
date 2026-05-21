<?php
// regression: strtotime supports the "weekday" and "fortnight" relative units.
// previously both returned false.
date_default_timezone_set('UTC');

// 2024-06-15 is a Saturday
$base = mktime(12, 0, 0, 6, 15, 2024);

foreach ([
    '+1 weekday',     // Sat -> Mon (skips Sun)
    '+2 weekdays',    // Sat -> Tue
    '-1 weekday',     // Sat -> Fri
    '-2 weekdays',    // Sat -> Thu
    '+5 weekdays',
    '+1 fortnight',   // +14 days
    '+2 fortnights',
    '-1 fortnight',
    '+1 weekday +3 hours',
] as $expr) {
    $t = strtotime($expr, $base);
    echo str_pad($expr, 22), ' => ', date('Y-m-d H:i:s D', $t), "\n";
}

// weekday stepping starting from a weekday
$wed = mktime(9, 0, 0, 6, 12, 2024); // Wednesday
echo 'from Wed +1 weekday: ', date('D', strtotime('+1 weekday', $wed)), "\n";   // Thu
echo 'from Wed +3 weekdays: ', date('D', strtotime('+3 weekdays', $wed)), "\n"; // Mon
echo 'from Wed -3 weekdays: ', date('D', strtotime('-3 weekdays', $wed)), "\n"; // Fri

// a DateTime modify with these units
$d = new DateTime('2024-06-15');
$d->modify('+1 fortnight');
echo $d->format('Y-m-d'), "\n";

// the plain units still work
echo date('Y-m-d', strtotime('+1 week', $base)), "\n";
echo date('Y-m-d', strtotime('+1 day', $base)), "\n";
