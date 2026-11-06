<?php
// a private property of an ancestor is invisible outside that ancestor: php
// treats the name as undeclared, so a read is undefined and a write makes a
// dynamic property beside the private one
class A { private $q = 'a'; public function readA() { return $this->q; } }
#[AllowDynamicProperties]
class B extends A { public function readB() { return $this->q ?? 'unset'; } public function writeB() { $this->q = 'b'; } }
$b = new B;
var_dump($b->readB());
$b->writeB();
var_dump($b->readB(), $b->readA());
print_r($b);
print_r((array)$b);
echo @$b->q, "\n";
$c = new B;
echo $c->q ?? 'none', "\n";
echo $c->q, "\n";
class C extends A {}
$x = new C;
$x->q = 'dyn';
print_r($x);
class E2 extends Exception { function f() { $this->string = 's'; return get_object_vars($this); } }
print_r(array_keys((new E2)->f()));
