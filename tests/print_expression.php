<?php

// print as statement
print "stmt\n";

// print returns 1 (used as expression)
$r = print "expr\n";
echo "r=$r\n";

// print inside arrow function
$f = fn($s) => print($s . "\n");
$f("from-arrow");

// print as part of larger expression
$count = 0;
$count += print "a\n";
$count += print "b\n";
echo "count=$count\n";

// print with no parens
$x = print "no-parens\n";
echo "x=$x\n";

// print inside ternary
$enabled = true;
$enabled ? print "on\n" : print "off\n";
