<?php
require __DIR__ . '/include/helper.php';
echo helper_greet("World") . "\n";

require __DIR__ . '/include/math_utils.php';
echo add(3, 4) . "\n";
echo multiply(5, 6) . "\n";

// require_once should not reload
require_once __DIR__ . '/include/helper.php';
require_once __DIR__ . '/include/helper.php';
echo "loaded once\n";

// include returns true on success
$result = include __DIR__ . '/include/helper.php';
echo $result ? "true" : "false";
echo "\n";
