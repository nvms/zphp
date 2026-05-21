<?php
// regression: file_put_contents() with an array argument writes the elements
// concatenated (like implode('', $array)). zphp coerced the whole array to
// the string "Array" instead.
$f = tempnam(sys_get_temp_dir(), 'zphp_fpc');

file_put_contents($f, ['x', 'y', 'z']);
echo file_get_contents($f), "\n";              // xyz

// mixed element types are each coerced to string
file_put_contents($f, ['a', 1, 2.5, true, false, null]);
echo file_get_contents($f), "\n";              // a12.51

// an empty array writes nothing
$n = file_put_contents($f, []);
echo "empty=", $n, " content=[", file_get_contents($f), "]\n";

// the return value is the number of bytes written
$n = file_put_contents($f, ['hello', ' ', 'world']);
echo "wrote=", $n, "\n";                       // wrote=11

// FILE_APPEND works with an array
file_put_contents($f, ['!', '!']);
file_put_contents($f, [' more'], FILE_APPEND);
echo file_get_contents($f), "\n";              // !! more

// a plain string still works unchanged
file_put_contents($f, 'plain string');
echo file_get_contents($f), "\n";

unlink($f);
