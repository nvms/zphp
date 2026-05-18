<?php
// regression: (string) cast on an array emits 'Array to string conversion'
// warning, same as concat/echo/printf %s/implode element. previously the
// cast_string opcode silently produced 'Array' without raising the warning
$a = [1, 2, 3];
$s = (string)$a;
echo $s . "\n";   // "Array"

// also fires via settype('string')
$b = ['x' => 1];
settype($b, 'string');
echo $b . "\n";

// suppress with @ silences the warning
$silenced = @(string)[9, 8, 7];
echo $silenced . "\n";

// no warning for scalars or strings
echo (string)42 . "\n";
echo (string)3.14 . "\n";
echo (string)true . "\n";
echo (string)null . "\n";   // ""
echo (string)"hi" . "\n";
