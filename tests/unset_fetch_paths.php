<?php
// unset() fetches the containers on its path for unsetting: a missing element
// is null without a warning, a string offset can't hold a property, and a
// static property named at run time is refused once its class is fetched

set_error_handler(function ($errno, $errstr) {
    echo "[$errno] $errstr\n";
});

class C {
    public static $s = 1;
}

$o = new stdClass;
$o->p = 1;
$o->q = 2;
$arr = ['o' => $o, 'n' => null];
unset($arr['o']->p);
unset($arr['missing']->p);
unset($arr['n']->p);
unset($arr['o']->q, $arr['other']->q->r);
var_dump($arr);

$str = 'abc';
foreach ([
    function () use ($str) { unset($str[0]->bar); },
    function () use ($str) { unset($str[0]->bar->baz); },
    function () use ($str) { unset($str['x']->bar); },
    function () { $name = 'foo'; unset(self::${$name . 'bar'}); },
    function () { $name = 's'; unset(C::${$name}); },
    function () { unset(C::${'nope'}); },
    function () { unset(Missing::${'nope'}); },
] as $f) {
    try {
        $f();
        echo "no error\n";
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
