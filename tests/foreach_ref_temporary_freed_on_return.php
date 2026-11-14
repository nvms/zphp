<?php
// a by-reference foreach over a temporary frees it when a return or break
// leaves the loop, as php's FE_FREE does

class Bag {
    public $a = 1;
    public $b = 2;
    public function __construct(private string $name) {}
    public function __destruct() { echo "free {$this->name}\n"; }
}

function first() {
    foreach (new Bag("first") as $k => &$v) {
        echo "visit $k\n";
        return $v;
    }
}
echo "got ", first(), "\n";

function nested() {
    foreach ([1, 2] as $i) {
        foreach (new Bag("inner $i") as &$v) {
            $v = 10;
            break 2;
        }
    }
    echo "after loops\n";
    var_dump(get_defined_vars());
}
nested();

class Throws {
    public $x = 1;
    public function __destruct() { echo "throwing\n"; throw new Exception("from destructor"); }
}

function thrower() {
    foreach (new Throws as &$v) {
        return 1;
    }
}
try {
    thrower();
} catch (Exception $e) {
    echo "caught ", $e->getMessage(), "\n";
}

foreach (new Bag("main") as &$v) {
    echo "main loop\n";
    break;
}
echo "after main loop\n";
var_dump(array_filter(array_keys(get_defined_vars()), fn($n) => str_starts_with($n, '__')));

foreach (new Throws as &$v) {
    return;
}
