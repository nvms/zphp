<?php
// a method call decides by-reference arguments from the method php will
// call: the calling scope's own private method, or __call (by value) for a
// method the scope can not see
class P {
    private function m(&$x) { $x = 'P::m'; }
    public function t() { $this->m($y); var_dump($y); }
}
class Q extends P { public function m($x) { echo "Q::m\n"; } }
(new Q)->t();

class D { private function method(&$x) { $x = 1; } protected function prot(&$x) { $x = 2; } }
class E extends D {
    public function __call($name, $args) { echo "__call $name\n"; }
    public function test() { $this->method($a); var_dump($a ?? 'unset'); $this->prot($b); var_dump($b); }
}
(new E)->test();
class F { public function __call($n, $a) { echo "__call $n\n"; } protected function prot(&$x) { $x = 3; } }
function outside() { (new F)->prot($z); var_dump($z ?? 'unset'); }
outside();
