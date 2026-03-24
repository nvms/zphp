<?php

// string + int coercion
echo "3" + 4 . "\n";
echo "3.5" * 2 . "\n";
echo "10" - "3" . "\n";

// bool in arithmetic
echo true + 1 . "\n";
echo false + 1 . "\n";
echo true + true . "\n";

// null in arithmetic
echo null + 5 . "\n";
echo null . "hello" . "\n";

// loose comparison - well-defined cases
echo var_export("0" == false, true) . "\n";
echo var_export("" == false, true) . "\n";
echo var_export(1 == "1", true) . "\n";
echo var_export(null == false, true) . "\n";
echo var_export(null === false, true) . "\n";

// spaceship with different types
echo (1 <=> 2) . "\n";
echo ("a" <=> "b") . "\n";
echo ("b" <=> "a") . "\n";
echo ("abc" <=> "abc") . "\n";
echo (1.5 <=> 1.5) . "\n";
echo (1.5 <=> 2.5) . "\n";
