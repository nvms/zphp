<?php
// regression: mt_rand throws ValueError when max < min ('Argument #2 ($max)
// must be greater than or equal to argument #1 ($min)'). rand silently
// swaps the args - a historical alias quirk PHP preserves. previously
// zphp's native_rand returned $min for both functions when max < min

try { mt_rand(5, 1); }
catch (\ValueError $e) { echo "mt: " . $e->getMessage() . "\n"; }

try { mt_rand(100, 50); }
catch (\ValueError $e) { echo "mt2: " . $e->getMessage() . "\n"; }

// rand silently swaps (no throw)
$v = rand(5, 1);
echo "rand-in-range: " . (($v >= 1 && $v <= 5) ? 'y' : 'n') . "\n";

// equal min/max returns that value
echo mt_rand(7, 7) . "\n";
echo rand(7, 7) . "\n";

// normal case works
$v = mt_rand(1, 10);
echo "mt-in-range: " . (($v >= 1 && $v <= 10) ? 'y' : 'n') . "\n";
