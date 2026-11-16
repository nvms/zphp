<?php
// ++/-- on a readonly property reads it, steps the copy and writes it back:
// for an object the write's readonly error wins, carrying the step's
// TypeError as its previous

class T {
    public readonly object $p;
    public readonly array $a;
    public readonly int $i;

    public function __construct() {
        $this->p = new stdClass;
        $this->a = [1];
        $this->i = 1;
    }

    public function bump() {
        $this->p++;
    }
}

$t = new T;
$cases = [
    'post inc' => fn() => $t->p++,
    'pre dec' => fn() => --$t->p,
    'array' => fn() => $t->a++,
    'int' => fn() => $t->i++,
    'in scope' => fn() => $t->bump(),
    'compound' => fn() => $t->p += 1,
];
foreach ($cases as $label => $f) {
    try {
        $f();
    } catch (Error $e) {
        echo $label, ': ', get_class($e), ': ', $e->getMessage();
        if ($prev = $e->getPrevious()) echo ' (previous ', get_class($prev), ': ', $prev->getMessage(), ')';
        echo "\n";
    }
}

// a plain property still reports the step error alone
$o = new stdClass;
$o->p = new stdClass;
try {
    $o->p++;
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), ' ', var_export($e->getPrevious(), true), "\n";
}
var_dump($t, new stdClass);
