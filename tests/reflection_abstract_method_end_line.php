<?php
// a method without a body ends on the line of its `;`

interface I {
    public function one();
    public function two(
        int $a,
        int $b
    ): int;
}

abstract class A {
    abstract protected function three(
        $x = [1, 2]
    );
    public function four() {
        return 4;
    }
}

foreach ([['I', 'one'], ['I', 'two'], ['A', 'three'], ['A', 'four']] as [$c, $m]) {
    $r = new ReflectionMethod($c, $m);
    echo "$c::$m ", $r->getStartLine(), "-", $r->getEndLine(), "\n";
}
