<?php
// a nested write through an ArrayAccess object writes into what offsetGet
// returned: a value that isn't an object or a reference is a copy, so php
// notices and the write has no effect

set_error_handler(function ($no, $msg, $file, $line) {
    echo "notice: $msg (line $line)\n";
    return true;
});

class Store implements ArrayAccess {
    public $data = ['a' => ['name' => 'Foo'], 'n' => 1, 'o' => null];

    function offsetExists($k): bool { echo "exists($k)\n"; return isset($this->data[$k]); }
    function offsetGet($k): mixed { echo "get($k)\n"; return $this->data[$k] ?? null; }
    function offsetSet($k, $v): void { echo "set($k)\n"; $this->data[$k] = $v; }
    function offsetUnset($k): void { echo "unset($k)\n"; unset($this->data[$k]); }
}

$s = new Store;
$s['a']['name'] = 'Bar';
var_dump($s->data['a']['name']);
$s['a']['name'] .= 'Baz';
var_dump($s->data['a']['name']);
$s['a']['x']['y'] = 1;
var_dump(isset($s->data['a']['x']));
$s['n']++;
var_dump($s->data['n']);
$s['o'][] = 5;
var_dump($s->data['o']);

class Holder implements ArrayAccess {
    public $inner;
    function __construct() { $this->inner = new Store; }
    function offsetExists($k): bool { return true; }
    function offsetGet($k): mixed { echo "holder get($k)\n"; return $this->inner; }
    function offsetSet($k, $v): void { echo "holder set($k)\n"; }
    function offsetUnset($k): void {}
}

$h = new Holder;
$h['x']['n'] = 10;
var_dump($h->inner->data['n']);

$ao = new ArrayObject(['a' => ['b' => 1]]);
$ao['a']['b'] = 2;
var_dump($ao['a']['b']);
