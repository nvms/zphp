<?php
// an object unserialize() made for a class it couldn't load refuses every
// property and method access, as php's incomplete_class.c handlers do

$o = unserialize('O:7:"Missing":2:{s:1:"p";i:1;s:1:"q";a:1:{i:0;i:2;}}');
var_dump($o);
var_dump(get_class($o), is_object($o));

var_dump($o->p);
var_dump($o->nothing ?? "default");
var_dump(isset($o->p), empty($o->p));

$attempts = [
    'write' => function () use ($o) { $o->p = 2; },
    'new property' => function () use ($o) { $o->r = 3; },
    'unset' => function () use ($o) { unset($o->p); },
    'reference' => function () use ($o) { $x = 1; $o->p = &$x; },
    'method' => function () use ($o) { $o->f(); },
    'dynamic method' => function () use ($o) { $m = 'g'; $o->$m(); },
];
foreach ($attempts as $what => $attempt) {
    try {
        $attempt();
        echo "$what: no error\n";
    } catch (Error $e) {
        echo "$what: ", $e->getMessage(), "\n";
    }
}
var_dump($o);

function readInFunction($o) {
    return $o->p;
}
var_dump(readInFunction($o));

class Reader {
    function read($o) { return $o->q; }
}
var_dump((new Reader)->read($o));

// objects of the class itself name no class
$bare = new __PHP_Incomplete_Class;
var_dump($bare);
try {
    $bare->x = 1;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump(unserialize(serialize($bare)));
var_dump(serialize($o));

$r = new ReflectionClass('__PHP_Incomplete_Class');
var_dump($r->isFinal(), $r->isInternal());

// read-modify-writes fetch the property for writing
foreach ([
    'concat' => function () use ($o) { $o->p .= 'x'; },
    'pre-increment' => function () use ($o) { ++$o->p; },
    'post-decrement' => function () use ($o) { $o->p--; },
    'append' => function () use ($o) { $o->q[] = 1; },
] as $what => $attempt) {
    try {
        $attempt();
        echo "$what: no error\n";
    } catch (Error $e) {
        echo "$what: ", $e->getMessage(), "\n";
    }
}
