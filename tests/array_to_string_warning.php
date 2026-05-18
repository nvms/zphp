<?php
// regression: PHP emits 'Array to string conversion' warning whenever an
// array gets coerced to string. zphp previously silently produced 'Array'
// without the warning at: concat (.), concat-assign (.=), echo, printf
// %s specifier, implode element

echo [1, 2] . "\n";
echo "x: " . [99] . "\n";

$x = [1, 2];
echo $x . "\n";

$buf = "start";
$buf .= [99];
echo "$buf\n";

printf("[%s]\n", [1, 2]);
echo sprintf("v=[%s]", [1]) . "\n";

// implode with nested arrays - one warning per inner array element
echo implode("|", [[1,2], [3,4], 'ok']) . "\n";

// no warning when array is the only operand (no coercion needed)
echo count([1,2,3]) . "\n";
