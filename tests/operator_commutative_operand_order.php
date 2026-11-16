<?php
// php's vm runs *, &, | and ^ with the operand of the lower kind second
// (constant < temporary < call result < variable), so a TypeError names the
// operands swapped; the integer operators warn about a lossy float on the
// left before refusing the right

set_error_handler(function ($errno, $errstr) {
    echo "Warning: $errstr\n";
});

function f() { return []; }
class C { function m() { return new stdClass; } }

$o = new stdClass;
$a = [];
$c = new C;
$fl = 3.5;
$cases = [
    'const * var' => fn() => 2 * $o,
    'var * const' => fn() => $o * 2,
    'array literal * new' => fn() => [] * new stdClass,
    'new * array literal' => fn() => new stdClass * [],
    'call * var' => fn() => f() * $o,
    'var * call' => fn() => $o * f(),
    'method * var' => fn() => $c->m() * $a,
    'dim * var' => fn() => $a[0] ?? [] * $o,
    'tmp * call' => fn() => ($a + []) * $c->m(),
    'call * tmp' => fn() => $c->m() * ($a + []),
    'strlen * var' => fn() => strlen('x') * $a,
    'const & var' => fn() => 1 & $a,
    'const | new' => fn() => 1 | new stdClass,
    'call ^ var' => fn() => f() ^ $fl,
    'var ^ var' => fn() => $a ^ $o,
    'const - var' => fn() => 2 - $o,
    'float % array' => fn() => 3.5 % [],
    'var % array' => fn() => $fl % $a,
    'array % float' => fn() => [] % 3.5,
    'float << array' => fn() => $fl << $a,
    'float & array' => fn() => $fl & $a,
    'string-float | array' => fn() => "1.5" | $a,
];
foreach ($cases as $label => $f) {
    try {
        $f();
        echo "$label: no error\n";
    } catch (Throwable $e) {
        echo "$label: ", $e->getMessage(), "\n";
    }
}

// the results don't change
$x = 6;
$s = "ab";
var_dump(3 * $x, $x * 3, 5 & $x, 5 | $x, 5 ^ $x, f() + [1], "AB" | $s, "AB" & $s, "AB" ^ $s, 2.5 * $x);
