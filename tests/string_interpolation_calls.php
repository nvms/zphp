<?php
// regression: complex {$...} string interpolation now supports a variable
// function call and a dynamic property name. previously {$fn('x')} printed
// the function name verbatim and {$obj->$prop} threw a fatal "could not be
// converted to string".

// variable holding a function name, called inside interpolation
$fn = 'strtoupper';
echo "result: {$fn('hello')}\n";

$repeat = 'str_repeat';
echo "repeated: {$repeat('ab', 3)}\n";

// a closure stored in a variable
$inc = fn($n) => $n + 1;
echo "incremented: {$inc(41)}\n";

// a callable pulled from an array element
$ops = ['rev' => 'strrev'];
echo "reversed: {$ops['rev']('abcdef')}\n";

// dynamic property name in interpolation
$obj = (object)['title' => 'Hello', 'body' => 'World'];
$field = 'title';
echo "field: {$obj->$field}\n";

// dynamic property chained to a further access
$nested = (object)['inner' => (object)['leaf' => 'X']];
$name = 'inner';
echo "chained: {$nested->$name->leaf}\n";

// dynamic property on a class instance
class Record {
    public $name = 'Record-A';
    public function label(): string { return 'L:' . $this->name; }
}
$r = new Record;
$prop = 'name';
echo "rec: {$r->$prop}\n";
echo "method: {$r->label()}\n";

// the literal forms still work unchanged
$plain = 'value';
echo "plain: $plain and {$plain}\n";
echo "literal prop: {$obj->title}\n";
$list = [10, 20, 30];
echo "index: {$list[1]}\n";
