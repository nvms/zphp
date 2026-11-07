<?php
// new with a class name held in a variable passes a variadic constructor
// its arguments as new with a written class name does

class Collect {
    public array $all;
    public $first;
    function __construct($first = 'none', ...$rest) {
        $this->first = $first;
        $this->all = $rest;
    }
}

$cn = 'Collect';
foreach ([[], [1], [1, 2, 3], range(1, 300)] as $args) {
    $a = new $cn(...$args);
    $b = new Collect(...$args);
    echo $a->first, ' ', count($a->all), ' | ', $b->first, ' ', count($b->all), "\n";
}
$o = new $cn('x', 'y', 'z');
var_dump($o->first, $o->all);
$o = new $cn();
var_dump($o->first, $o->all);
$obj = new Collect;
$o = new $obj(7, 8);
var_dump($o->first, $o->all);
