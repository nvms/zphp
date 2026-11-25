<?php
// RecursiveIteratorIterator, SplFileObject and GlobIterator refuse every
// method call (their own, a subclass's, magic or not) on an object whose
// parent constructor never ran; IteratorIterator's method_exists() sees the
// methods it forwards to its inner iterator

class R extends RecursiveIteratorIterator {
    public function __construct() {}
    public function mine() { return "mine"; }
}
class F extends SplFileObject {
    public function __construct() {}
    public function fpassthru(): int { return 0; }
    public function mine() { return "mine"; }
}
class G extends GlobIterator {
    public function __construct() {}
    public function mine() { return "mine"; }
}
class D extends DirectoryIterator {
    public function __construct() {}
    public function mine() { return "mine"; }
}

foreach ([new R, new F, new G, new D] as $o) {
    foreach (['mine', 'fpassthru', 'valid', 'nope'] as $m) {
        try {
            if (!method_exists($o, $m)) continue;
        } catch (Error $e) {
            echo "method_exists(", get_class($o), ", $m): ", $e->getMessage(), "\n";
            continue;
        }
        try {
            var_dump($o->$m());
        } catch (Error $e) {
            echo get_class($o), "->$m(): ", get_class($e), ": ", $e->getMessage(), "\n";
        }
    }
    try {
        var_dump($o->mine());
    } catch (Error $e) {
        echo get_class($o), "->mine(): ", $e->getMessage(), "\n";
    }
}

// constructed ones work
$r = new RecursiveIteratorIterator(new RecursiveArrayIterator([1, [2]]));
var_dump(iterator_to_array($r, false));
$t = new SplTempFileObject();
var_dump($t->fwrite("x"));

$it = new IteratorIterator(new ArrayIterator([1, 2, 3]));
var_dump(method_exists($it, 'offsetGet'), method_exists($it, 'count'), method_exists($it, 'nope'));
foreach ($it as $v) {
    if (method_exists($it, 'offsetGet')) var_dump($it->offsetGet(1));
}
$ii = new IteratorIterator(new IteratorIterator(new ArrayIterator([1])));
var_dump(method_exists($ii, 'getArrayCopy'));
