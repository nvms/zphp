<?php
// regression: strtotime handles "midnight"/"noon" combined with a date
// expression. PHP applies tokens left to right - a trailing midnight/noon
// overrides the time-of-day, a leading one is overridden by a following
// date keyword. zphp previously returned false for every combination.
date_default_timezone_set('UTC');
$base = mktime(15, 30, 45, 6, 15, 2024); // Sat 2024-06-15 15:30:45

foreach ([
    'midnight tomorrow',                 // 2024-06-16 00:00:00
    'tomorrow midnight',                 // 2024-06-16 00:00:00
    'tomorrow noon',                     // 2024-06-16 12:00:00
    'noon tomorrow',                     // 2024-06-16 00:00:00 (tomorrow resets)
    'yesterday midnight',                // 2024-06-14 00:00:00
    'midnight yesterday',                // 2024-06-14 00:00:00
    'today midnight',                    // 2024-06-15 00:00:00
    'midnight today',                    // 2024-06-15 00:00:00
    '+1 day midnight',                   // 2024-06-16 00:00:00
    'next monday noon',                  // 2024-06-17 12:00:00
    'first day of next month midnight',  // 2024-07-01 00:00:00
    'last day of this month noon',       // 2024-06-30 12:00:00
] as $expr) {
    $t = strtotime($expr, $base);
    echo str_pad($expr, 34), ' => ', date('Y-m-d H:i:s', $t), "\n";
}

// bare midnight / noon still work
echo date('H:i:s', strtotime('midnight', $base)), "\n";   // 00:00:00
echo date('H:i:s', strtotime('noon', $base)), "\n";       // 12:00:00

// leading noon applied to a pure relative adjustment
echo date('H:i:s', strtotime('noon +3 hours', $base)), "\n";  // 15:00:00
