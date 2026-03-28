<?php
// inline assignment in comparison (PHP allows $var = expr as rhs of any operator)
if (false === $x = 5) {
    echo "wrong\n";
} else {
    echo "x=$x\n";
}

// with function call
if (false === $len = strlen("hello")) {
    echo "wrong\n";
} else {
    echo "len=$len\n";
}

// with parse_url (the exact pattern from Symfony)
$uri = "http://localhost";
if (false === $components = parse_url($uri)) {
    echo "wrong\n";
} else {
    echo "scheme=" . $components['scheme'] . "\n";
    echo "host=" . $components['host'] . "\n";
}

// assignment in while condition
$items = [10, 20, 30];
$i = 0;
while (false !== $val = ($i < count($items) ? $items[$i++] : false)) {
    echo "val=$val\n";
}

// nested: $a === $b = $c should be $a === ($b = $c)
$result = (1 === $y = 1);
echo "result=" . ($result ? "true" : "false") . "\n";
echo "y=$y\n";

// negative string index
$s = "hello";
echo "last=" . $s[-1] . "\n";
echo "second_last=" . $s[-2] . "\n";
echo "ord_last=" . ord($s[-1]) . "\n";
