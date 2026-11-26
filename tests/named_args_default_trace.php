<?php
// a default that fails while named arguments are bound is evaluated in the
// callee's frame: its trace entry shows the arguments so far, a skipped one
// as NULL

function test3($a = SOME_OTHER_CONST, $b = 'b') {
    echo "a: $a, b: $b\n";
}
function test4($a = 1, $b = UNDEFINED_B, $c = 'c', $d = 'd') {}
function test5($a = new ArrayObject([UNDEFINED_E]), $b = 'b') {}

class K {
    public function m($x = 'x', $y = UNDEFINED_Y, $z = 'z') {}
    public static function s($x = UNDEFINED_S, $y = 'y') {}
    public function __construct($p = UNDEFINED_P, $q = 'q') {}
}
class L {
    public function __construct($p = 'p', $q = 'q') { var_dump($p, $q); }
}
// a null passed by name is passed
new L(p: null);
new L(q: null);

$calls = [
    fn() => test3(b: 'B'),
    fn() => test4(c: 'C'),
    fn() => test4(d: 'D'),
    fn() => test4(1, d: 'D'),
    fn() => test5(b: 'B'),
    fn() => (new K(q: 1))->m(z: 'Z'),
    fn() => K::s(y: 'Y'),
    fn() => new K(q: 'Q'),
    fn() => call_user_func_array('test3', ['b' => 'B']),
    fn() => test3(...['b' => 'B']),
];
foreach ($calls as $call) {
    try {
        $call();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
        foreach ($e->getTrace() as $frame) {
            if (!isset($frame['function']) || str_starts_with($frame['function'], '{closure')) continue;
            echo "  ", $frame['class'] ?? '', $frame['type'] ?? '', $frame['function'], "(";
            echo implode(', ', array_map(fn($a) => var_export($a, true), $frame['args'] ?? [])), ")\n";
        }
    }
}
