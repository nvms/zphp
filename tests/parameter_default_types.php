<?php
// defaults against their parameter's type: an int default of a float
// parameter is a float, and a default from a constant is checked when used

const NUMBER = 7;
const TEXT = "seven";
const NUMERIC = "8";
const NOTHING = null;

function f(float $x = 0) { var_dump($x); }
function g(int|float $x = 1) { var_dump($x); }
function h(int $x = NUMBER) { var_dump($x); }
function i(int $x = NUMERIC) { var_dump($x); }
function j(int $x = TEXT) { var_dump($x); }
function k(int $x = NOTHING) { var_dump($x); }
function l(?float $x = NUMBER) { var_dump($x); }

class Holder
{
    public float $f = 3;
    public function m(float $x = 2) { var_dump($x); }
}

f();
g();
h();
i();
foreach (['j', 'k'] as $fn) {
    try {
        $fn();
    } catch (TypeError $e) {
        echo preg_replace('/, called in .*/', '', $e->getMessage()), "\n";
    }
}
l();
(new Holder)->m();
var_dump((new Holder)->f);
var_dump((new ReflectionParameter('f', 0))->getDefaultValue());
