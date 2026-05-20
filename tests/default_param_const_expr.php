<?php
// regression: constant-expression default parameter values that the compiler
// must fold. previously zphp's evalConstExpr only handled int arithmetic +
// literals + arrays, so string concat, ternary, and shift/modulo defaults
// silently came back empty/null.
function f_concat($a = 'x' . 'y') { return $a; }
function f_concat_chain($a = 'pre-' . 'fix' . '-suf') { return $a; }
function f_concat_mixed($a = 'count: ' . 5) { return $a; }
function f_ternary($a = true ? 'yes' : 'no') { return $a; }
function f_ternary_false($a = false ? 'yes' : 'no') { return $a; }
function f_short_ternary($a = 0 ?: 'fallback') { return $a; }
function f_shift($a = 1 << 4) { return $a; }
function f_shift_r($a = 256 >> 2) { return $a; }
function f_mod($a = 17 % 5) { return $a; }
function f_arith($a = 2 + 3 * 4) { return $a; }
function f_bitwise($a = 0xF0 | 0x0F) { return $a; }
function f_neg($a = -42) { return $a; }
function f_nested_ternary($a = (5 > 3) ? ('a' . 'b') : 'c') { return $a; }

echo f_concat(), "\n";
echo f_concat_chain(), "\n";
echo f_concat_mixed(), "\n";
echo f_ternary(), "\n";
echo f_ternary_false(), "\n";
echo f_short_ternary(), "\n";
echo f_shift(), "\n";
echo f_shift_r(), "\n";
echo f_mod(), "\n";
echo f_arith(), "\n";
echo f_bitwise(), "\n";
echo f_neg(), "\n";
echo f_nested_ternary(), "\n";

// explicit args still override the default
echo f_concat('explicit'), "\n";
echo f_ternary('override'), "\n";

// method default params
class C {
    public function m($x = 'a' . 'b' . 'c', $y = 3 ** 2) { return "$x:$y"; }
}
echo (new C)->m(), "\n";
