<?php
// an error handler that releases the object whose dynamic property creation
// it was told about: the object is destroyed and the creation refused
set_error_handler(function ($code, $msg) {
    echo "handler: $msg\n";
    $GLOBALS['a'] = null;
    return true;
});

class D {
    public function __destruct() { echo "destruct\n"; }
}

$a = new D;
try {
    [&$a->y];
} catch (Throwable $ex) {
    echo $ex::class, ': ', $ex->getMessage(), "\n";
}
var_dump($a);

$a = new D;
try {
    $a->z = 1;
} catch (Throwable $ex) {
    echo $ex::class, ': ', $ex->getMessage(), "\n";
}
var_dump($a);

$a = new D;
try {
    $r = &$a->w;
} catch (Throwable $ex) {
    echo $ex::class, ': ', $ex->getMessage(), "\n";
}
var_dump($a);

$a = new D;
try {
    $a->v[] = 1;
} catch (Throwable $ex) {
    echo $ex::class, ': ', $ex->getMessage(), "\n";
}
var_dump($a);

foreach (['dim' => fn() => $GLOBALS['a']->d['k'] = 1, 'concat' => fn() => $GLOBALS['a']->c .= 'x',
          'inc' => fn() => $GLOBALS['a']->i++, 'nested' => fn() => $GLOBALS['a']->n->x = 1] as $label => $f) {
    echo "$label\n";
    $a = new D;
    try {
        $f();
    } catch (Throwable $ex) {
        echo $ex::class, ': ', $ex->getMessage(), "\n";
    }
    var_dump($a);
}

// a temporary the handler can't release keeps its property
function mk() { return new D; }
mk()->t[] = 1;
mk()->t .= 'x';

// a handler that keeps the object leaves the property created
set_error_handler(function ($code, $msg) {
    echo "handler: $msg\n";
    return true;
});
$b = new D;
$b->q = 2;
var_dump($b);
echo "done\n";
