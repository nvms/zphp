<?php
// alt-syntax switch: switch(): case: endswitch;

$x = 2;
switch ($x):
    case 1:
        echo "one\n";
        break;
    case 2:
    case 3:
        echo "two or three\n";
        break;
    default:
        echo "other\n";
endswitch;

// nested in alt-syntax foreach
$items = [10, 20, 30];
foreach ($items as $v):
    switch ($v):
        case 10:
            echo "ten\n";
            break;
        case 20:
            echo "twenty\n";
            break;
        default:
            echo "default: $v\n";
    endswitch;
endforeach;

// default only
$y = 99;
switch ($y):
    default:
        echo "only default\n";
endswitch;

// fallthrough (no break)
$z = 1;
switch ($z):
    case 1:
        echo "start\n";
    case 2:
        echo "fall\n";
        break;
    case 3:
        echo "nope\n";
        break;
endswitch;
