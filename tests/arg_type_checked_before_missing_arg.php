<?php
// each passed argument's type is checked before a missing one is reported,
// as php's RECV opcodes run in order
function two(int $a, int $b) { return $a + $b; }
class M {
    function two(int $a, int $b) { return $a + $b; }
    static function stat(int $a, int $b) { return $a + $b; }
}
$calls = [
    fn() => two("x"),
    fn() => two(1),
    fn() => "Hello" |> 'two',
    fn() => (new M)->two("x"),
    fn() => M::stat("x"),
    fn() => (new M)->two(1),
];
foreach ($calls as $call) {
    try {
        $call();
    } catch (Throwable $e) {
        echo get_class($e), ": ", preg_replace('/ in .* on line \d+/', '', $e->getMessage()), "\n";
    }
}
