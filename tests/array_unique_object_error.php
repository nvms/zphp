<?php
// SORT_STRING throws when comparing object without __toString to another value
$o = new stdClass; $o->n = 1;
try {
    array_unique([$o, 1]);
} catch (\Error $e) {
    echo "caught\n";
}

// single-element array with object: no comparison needed, no error
$res = array_unique([$o]);
echo count($res), "\n";

// SORT_REGULAR on objects: result is array
var_dump(is_array(array_unique([$o, new stdClass], SORT_REGULAR)));

// Object with __toString works in SORT_STRING
class Stringy {
    private $v;
    public function __construct($v) { $this->v = $v; }
    public function __toString(): string { return (string)$this->v; }
}
$res3 = array_unique([new Stringy(1), new Stringy(1), new Stringy(2)]);
echo count($res3), "\n";

// scalar tests
print_r(array_unique([1, '1', 1.0, true]));
print_r(array_unique([1, '1', 1.0, true], SORT_REGULAR));
print_r(array_unique([1, '1', 1.0, true], SORT_NUMERIC));
print_r(array_unique(['a', 'A', 'a'], SORT_STRING));

// preserves keys
$a = ['x' => 1, 'y' => 2, 'z' => 1];
print_r(array_unique($a));

// nested arrays
print_r(array_unique([1, [2], [2], 3], SORT_REGULAR));
