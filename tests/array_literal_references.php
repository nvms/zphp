<?php
$v = 4;
$a = ['z' => &$v, 'a' => 2];
ksort($a);
$a['z'] = 8;
var_dump($v);

// Keyed, unkeyed, mixed, numeric-string keys, and both write directions.
$x = 10;
$y = 20;
$a = [&$x, 'z' => &$y, 5 => &$x, '6' => &$y, 99];
$a[0] = 11;
$y = 21;
var_dump($x, $a[5], $a['z'], $a[6], $a[7]);

// COW copies keep reference entries shared, ordinary entries independent.
$b = $a;
$b[5] = 12;
$b[7] = 100;
var_dump($x, $a[0], $a[7], $b[7]);
unset($x, $y, $a);
$b[0] = 13;
var_dump($b[5]);

// Duplicate keys replace a reference instead of assigning through it.
$x = 1;
$y = 2;
$a = ['k' => &$x, 'k' => 3];
$a['k'] = 4;
var_dump($x, $a['k']);
$a = ['k' => &$x, 'k' => &$y];
$x = 5;
$a['k'] = 6;
var_dump($x, $y, $a['k']);

// Sources use the same binding path as explicit reference assignments.
class LiteralReferenceBox {
    public $value = 30;
    public static $shared = 40;
    public function &getValue() { return $this->value; }
}
$box = new LiteralReferenceBox;
$name = 'value';
$source = ['nested' => ['value' => 50]];
$a = ['p' => &$box->$name, &LiteralReferenceBox::$shared,
      'n' => &$source['nested']['value'], &$box->value];
$a['p'] = 31;
$a[0] = 41;
$a['n'] = 51;
$a[1] = 32;
var_dump($box->value, LiteralReferenceBox::$shared, $source['nested']['value'], $a['p']);

function literalLocalReferences() {
    $local = ['value' => 60];
    return ['first' => &$local['value'], &$local['value']];
}
$a = literalLocalReferences();
$b = $a;
unset($a);
$b[0] = 61;
var_dump($b['first']);

// Array-valued cells do not leak writes into pre-reference value copies.
$value = ['n' => 1];
$copy = $value;
$a = [&$value];
$a[0]['n'] = 2;
var_dump($value['n'], $copy['n']);

// Reference cells outlive their source object and source frame.
function literalObjectReferences() {
    $box = new LiteralReferenceBox;
    return [&$box->value, 'same' => &$box->value];
}
$a = literalObjectReferences();
$a[0] = 70;
var_dump($a['same']);

// Reading a referenced element by value must not capture the cell.
$v = 80;
$a = [&$v, 'value' => $v];
$v = 81;
var_dump($a[0], $a['value']);

// Unset removes only the binding; reusing the name creates new storage.
unset($v);
$v = 82;
$a[0] = 83;
var_dump($v, $a[0]);

// Two escaped aliases keep object values alive until the last array dies.
class LiteralReferencePayload {
    public $n = 90;
    public function __destruct() { echo "payload destroyed\n"; }
}
function literalPayloadReferences() {
    $value = new LiteralReferencePayload;
    return [&$value, 'same' => &$value];
}
$a = literalPayloadReferences();
$b = $a;
unset($a);
$b[0]->n = 91;
var_dump($b['same']->n);
unset($b);
echo "done\n";

// Reference acquisition in literals must separate dimension containers too.
$source = ['n' => 1];
$copy = $source;
$a = [&$source['n']];
$a[0] = 2;
var_dump($source['n'], $copy['n']);
$box = new LiteralReferenceBox;
$box->value = ['n' => 3];
$copy = $box->value;
$a = [&$box->value];
$a[0]['n'] = 4;
var_dump($box->value['n'], $copy['n']);
LiteralReferenceBox::$shared = ['n' => 5];
$copy = LiteralReferenceBox::$shared;
$a = [&LiteralReferenceBox::$shared];
$a[0]['n'] = 6;
var_dump(LiteralReferenceBox::$shared['n'], $copy['n']);
