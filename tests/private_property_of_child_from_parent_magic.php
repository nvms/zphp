<?php
// a parent class's method, a magic one included, runs in the parent's scope: it
// can't reach a private property its child declares, whatever the object
class Op { function __set($var, $value) { echo "set $var\n"; $this->$var = $value; } }
class Ext extends Op { private $x; }
$op = new Ext;
try { $op->x = 'test'; } catch (Error $e) { echo $e->getMessage(), "\n"; }
class Op2 { function __set($var, $value) { echo "set2 $var\n"; $this->x = $value; } }
class Ext2 extends Op2 { private $x; }
$op = new Ext2;
try { $op->x = 'test'; } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump($op);
class A { public function &__get($name) { echo "get $name\n"; return $this->test; } }
class B extends A { private $test; }
$b = new B;
try { var_dump($b->test); } catch (Error $e) { echo $e->getMessage(), "\n"; }
