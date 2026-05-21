<?php
// regression: the `xor` keyword operator is logical, not bitwise - it
// boolifies both operands and yields a bool. zphp compiled it to the
// bitwise-xor opcode, so `5 xor 0` returned int(5) instead of bool(true).
var_dump(5 xor 0);          // true
var_dump(0 xor 7);          // true
var_dump(1 xor 1);          // false
var_dump(0 xor 0);          // false
var_dump(true xor false);   // true
var_dump(true xor true);    // false
var_dump(false xor false);  // false

// truthiness of operands, not their values
var_dump('a' xor '');       // true
var_dump('0' xor 'x');      // true  ('0' is falsy)
var_dump(null xor 1);       // true
var_dump([] xor [1]);       // true
var_dump([1,2] xor [3]);    // false (both truthy)
var_dump(-1 xor 0);         // true  (-1 is truthy)

// xor has very low precedence: `$r = 3 xor 0` assigns 3 to $r first
$r = 3 xor 0;
var_dump($r);               // int(3)
$ok = (3 xor 0);
var_dump($ok);              // true

// usable in a condition
echo (5 xor 0) ? 'one-truthy' : 'no', "\n";
echo (1 xor 1) ? 'no' : 'both-or-neither', "\n";

// bitwise ^ is unaffected
var_dump(5 ^ 3);            // int(6)
var_dump(0xFF ^ 0x0F);      // int(240)
