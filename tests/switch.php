<?php

$x = 2;
switch ($x) {
    case 1:
        echo "one\n";
        break;
    case 2:
        echo "two\n";
        break;
    case 3:
        echo "three\n";
        break;
}

// default
$y = 99;
switch ($y) {
    case 1:
        echo "one\n";
        break;
    default:
        echo "other\n";
        break;
}

// fallthrough (case 1, 2, 3 share body)
$z = 2;
switch ($z) {
    case 1:
    case 2:
    case 3:
        echo "low\n";
        break;
    case 4:
    case 5:
        echo "high\n";
        break;
}

// fallthrough without break
$a = 1;
switch ($a) {
    case 1:
        echo "a";
    case 2:
        echo "b";
    case 3:
        echo "c";
        break;
    case 4:
        echo "d";
}
echo "\n";

// no match, no default
$b = 42;
switch ($b) {
    case 1:
        echo "nope\n";
        break;
}
echo "done\n";

// switch with strings
$lang = 'php';
switch ($lang) {
    case 'js':
        echo "javascript\n";
        break;
    case 'php':
        echo "php\n";
        break;
    case 'py':
        echo "python\n";
        break;
}
