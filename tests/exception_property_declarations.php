<?php
// Exception and Error declare php's properties: message, code, file and line
// protected, string, trace and previous private; reaching one from outside
// names the object's class
class Failed extends RuntimeException { public $extra = 1; }
$e = new Failed('m', 3);
var_dump($e);
print_r(array_keys((array)$e));
print_r(get_object_vars($e));
foreach (['message', 'code', 'file', 'line'] as $name) {
    try { echo $e->$name, "\n"; } catch (Error $x) { echo $x->getMessage(), "\n"; }
}
class Base { protected $p = 1; }
class Child extends Base {}
try { echo (new Child)->p; } catch (Error $x) { echo $x->getMessage(), "\n"; }
$c = new Child;
try { $c->p = 2; } catch (Error $x) { echo $x->getMessage(), "\n"; }
$r = new ReflectionProperty('Exception', 'previous');
var_dump($r->isPrivate(), (string)$r->getType());
