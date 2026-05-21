<?php
// regression: empty() uses isset-semantics - empty() on an uninitialized
// typed property must report "empty" without throwing the
// "must not be accessed before initialization" Error, the same way
// isset() and `??` already do.

class Box {
    public int $uninit;
    public ?int $nullableUninit;
    public int $zero = 0;
    public string $emptyStr = '';
    public int $set = 42;
    public array $items = [1, 2, 3];
}

$b = new Box;

// empty() on uninitialized typed properties - true, no error
var_dump(empty($b->uninit));          // true
var_dump(empty($b->nullableUninit));  // true

// empty() on initialized-but-falsy properties
var_dump(empty($b->zero));            // true
var_dump(empty($b->emptyStr));        // true

// empty() on truthy properties
var_dump(empty($b->set));             // false
var_dump(empty($b->items));           // false

// after writing an uninitialized property, empty() reflects the value
$b->uninit = 7;
var_dump(empty($b->uninit));          // false
$b->uninit = 0;
var_dump(empty($b->uninit));          // true

// empty() on a chained property where an intermediate is initialized
class Outer { public Inner $inner; }
class Inner { public int $n; }
$o = new Outer;
$o->inner = new Inner;
var_dump(empty($o->inner->n));        // true (n is uninitialized)
$o->inner->n = 5;
var_dump(empty($o->inner->n));        // false

// empty() on array elements still works (regression)
$arr = ['a' => 0, 'b' => 'x', 'c' => []];
var_dump(empty($arr['a']), empty($arr['b']), empty($arr['c']), empty($arr['missing']));

// empty() on plain variables (regression)
$v = 0;
var_dump(empty($v), empty($undefinedVariable));

// isset() on the same uninitialized typed properties stays correct
var_dump(isset($b->uninit), isset($b->set));

// `??` on an uninitialized typed property routes to the fallback
$b2 = new Box;
echo $b2->uninit ?? 'fallback', "\n";

// an inherited uninitialized typed property
class Base { public int $base; }
class Derived extends Base { public int $own; }
$d = new Derived;
var_dump(empty($d->base), empty($d->own));
