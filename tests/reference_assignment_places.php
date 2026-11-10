<?php
// `place = &place` for properties, static properties and array elements,
// with typed properties checking what they are bound to

class Node
{
    public $value = 1;
    public $alias;
    public static $shared = 0;
}

$a = new Node;
$a->alias = &$a->value;
$a->value = 5;
var_dump($a->alias);
$a->alias = 6;
var_dump($a->value);

$list = [1, 2];
$a->alias = &$list[1];
$list[1] = 9;
var_dump($a->alias, $a->value);

$b = new Node;
$b->alias = &$a->value;
$a->value = 10;
var_dump($b->alias);

Node::$shared = &$a->value;
$a->value = 11;
var_dump(Node::$shared);
Node::$shared = 12;
var_dump($a->value);

$c = [];
$c[0] = &$a->value;
$c['k'] = &Node::$shared;
$a->value = 13;
var_dump($c);

function &counter() { static $n = 0; return $n; }
$b->value = &counter();
$b->value = 41;
var_dump(counter());

function rebind(Node $n, array &$arr) { $n->alias = &$arr[0]; }
$arr = [100];
rebind($b, $arr);
$arr[0] = 101;
var_dump($b->alias);

unset($b->alias);
$arr[0] = 102;
var_dump(isset($b->alias), $arr[0]);

class Typed
{
    public int $int = 0;
    public float $float = 0.0;
    public ?int $nint = null;
    public ?string $nstring = null;
    public string|int $si = 0;
    public string|float $sf = 0.0;
    public static int $count = 0;
}

function bind(callable $f): void
{
    try {
        $f();
        echo "bound\n";
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}

$t = new Typed;
$ref = "42";
bind(function () use ($t, &$ref) { $t->int = &$ref; });
var_dump($ref);
bind(function () use ($t) { $t->float = &$t->int; });
bind(function () use ($t) { $t->nint = &$t->int; });
$t->int = 7;
var_dump($t->nint);
$str = "x";
bind(function () use ($t, &$str) { $t->nint = &$str; });
$t2 = new Typed;
$shared = "1";
$t2->si = &$shared;
bind(function () use ($t2, &$shared) { $t2->sf = &$shared; });
bind(function () use (&$shared) { $shared = 42; });
bind(function () use (&$shared) { $shared = 4.5; });
var_dump($shared);
$value = "7";
bind(function () use (&$value) { Typed::$count = &$value; });
var_dump(Typed::$count, $value);
$value = 8;
var_dump(Typed::$count);
bind(function () use (&$value) { $value = "eight"; });
