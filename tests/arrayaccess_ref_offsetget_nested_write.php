<?php
// `$obj[a][b] = v` on an ArrayAccess object whose offsetGet() returns by
// reference writes through the reference, never calling offsetSet()
class A implements ArrayAccess {
    public $foo = [];
    public function &offsetGet($n): mixed { echo "get $n\n"; return $this->foo[$n]; }
    public function offsetSet($n, $v): void { echo "set $n\n"; }
    public function offsetUnset($n): void {}
    public function offsetExists($n): bool { return true; }
}
$a = new A;
$a['foo']['bar'] = 2;
$a['foo']['baz'] = 3;
$a['arr'] = 1;
$a->foo['list'] = [1];
$copy = $a->foo['list'];
$a['list'][] = 2;
$a['list'][5] = 6;
$a->foo['str'] = 'abc';
$a['str'][1] = 'X';
$a['x'][] = 3;
$a['w']['q']['r'] = 1;
var_dump($a->foo, $copy);

class B implements ArrayAccess {
    public $data = [];
    public function offsetGet($n): mixed { echo "get $n\n"; return $this->data[$n] ?? null; }
    public function offsetSet($n, $v): void { echo "set $n\n"; $this->data[$n] = $v; }
    public function offsetUnset($n): void {}
    public function offsetExists($n): bool { return true; }
}
$b = new B;
$b['k']['bar'] = 2;
var_dump($b->data);
