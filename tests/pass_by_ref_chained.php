<?php

// === chained property ref: $obj->a->b ===

class Inner {
    public $value = 0;
    public $name = "hello";
}

class Outer {
    public $inner;
    public function __construct() {
        $this->inner = new Inner();
    }
}

function inc_ref(&$x) { $x++; }
function set_ref(&$x, $val) { $x = $val; }
function append_ref(&$s, $suffix) { $s .= $suffix; }

// basic chained property ref
$obj = new Outer();
inc_ref($obj->inner->value);
inc_ref($obj->inner->value);
inc_ref($obj->inner->value);
echo $obj->inner->value . "\n"; // 3

// string chained property ref
$obj2 = new Outer();
append_ref($obj2->inner->name, " world");
echo $obj2->inner->name . "\n"; // hello world

// set via chained ref
$obj3 = new Outer();
set_ref($obj3->inner->value, 42);
echo $obj3->inner->value . "\n"; // 42

// swap chained prop with simple var
function swap_vals(&$a, &$b) { $temp = $a; $a = $b; $b = $temp; }
$obj4 = new Outer();
$obj4->inner->value = 10;
$other = 99;
swap_vals($obj4->inner->value, $other);
echo $obj4->inner->value . "\n"; // 99
echo $other . "\n"; // 10

// === dynamic property ref: $obj->$var ===

class DynTarget {
    public $count = 0;
    public $name = "test";
}

$dt = new DynTarget();
$prop = "count";
inc_ref($dt->$prop);
inc_ref($dt->$prop);
echo $dt->count . "\n"; // 2

// dynamic string property
$dt2 = new DynTarget();
$prop2 = "name";
append_ref($dt2->$prop2, "_suffix");
echo $dt2->name . "\n"; // test_suffix

// dynamic swap
$dt3 = new DynTarget();
$dt3->count = 50;
$prop3 = "count";
$x = 75;
swap_vals($dt3->$prop3, $x);
echo $dt3->count . "\n"; // 75
echo $x . "\n"; // 50

// === three-level chain: $obj->a->b->c ===

class Deep {
    public $mid;
    public function __construct() {
        $this->mid = new Outer();
        $this->mid->inner = new Inner();
    }
}

$deep = new Deep();
inc_ref($deep->mid->inner->value);
inc_ref($deep->mid->inner->value);
echo $deep->mid->inner->value . "\n"; // 2

echo "done\n";
