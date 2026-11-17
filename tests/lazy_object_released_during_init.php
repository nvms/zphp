<?php
// an initializer that drops the last reference to the lazy object it
// initializes releases it: its destructor runs and the access that
// triggered the initialization fails

class C {
    public $s;
    public function __destruct() {
        echo "destructor\n";
    }
}

$r = new ReflectionClass(C::class);

echo "ghost:\n";
$o = $r->newLazyGhost(function ($obj) {
    global $o;
    $o = null;
});
try {
    $o->s = 1;
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

echo "proxy:\n";
$o = $r->newLazyProxy(function ($obj) {
    global $o;
    $o = null;
    return new C();
});
try {
    var_dump($o->s);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

echo "initializer error:\n";
$o = $r->newLazyGhost(function ($obj) {
    global $o;
    $o = null;
    return 1;
});
try {
    $o->s = 1;
} catch (Error $e) {
    do {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    } while ($e = $e->getPrevious());
}

echo "still referenced:\n";
$o = $r->newLazyGhost(function ($obj) {
    global $o, $keep;
    $keep = $o;
    $o = null;
});
$o->s = 2;
var_dump($keep->s);
echo "done\n";
