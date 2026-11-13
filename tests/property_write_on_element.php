<?php
// the container of a property write is fetched for writing: an element
// chain is created, a missing element is null, and the write refuses it

function attempt(callable $f) {
    try {
        $f();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

attempt(function () {
    $arr[1][2][3]->foo = 1;
    var_dump($arr);
});
attempt(function () {
    $arr[][]->bar = 2;
    var_dump($arr);
});
attempt(function () {
    $null->a['hello']->b = 42;
});
attempt(function () {
    $b = [1 => null];
    $b[1]->x++;
});
attempt(function () {
    $c = [1 => [2]];
    $c[1]->x = 1;
});
attempt(function () {
    $c = [1 => 5];
    $c[1]->x = 1;
});
attempt(function () {
    $d = [];
    $d['k'][]->x = 1;
    var_dump($d);
});
attempt(function () {
    $b = [1 => 'abc'];
    $b[1]->x = 1;
});
attempt(function () {
    $b = ['k' => []];
    $b['k'][1]->x += 1;
});
attempt(function () {
    $str = "x";
    $str[0]->bar = 1;
});
attempt(function () {
    $str = "x";
    $str[0]->bar .= 1;
});
attempt(function () {
    $str = "x";
    $str[0]->bar = &$ref;
});
attempt(function () {
    $o = [new stdClass];
    $copy = $o;
    $o[0]->p = 5;
    $o[0]->list[] = 1;
    var_dump($o, $copy);
});
attempt(function () {
    $x = null;
    $x->p = &$y;
});
attempt(function () {
    $holder = new stdClass;
    $holder->items['a']->name = 'n';
});
