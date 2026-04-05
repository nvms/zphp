<?php

// argument swapping
echo sprintf('%2$s %1$s', 'world', 'hello') . "\n";
echo sprintf('%1$s is %2$d', 'age', 25) . "\n";
echo sprintf('%3$s-%2$s-%1$s', 'c', 'b', 'a') . "\n";

// dynamic precision
echo sprintf('%.*f', 2, 3.14159) . "\n";
echo sprintf('%.*f', 4, 3.14159) . "\n";
echo sprintf('%.*f', 0, 3.14159) . "\n";
