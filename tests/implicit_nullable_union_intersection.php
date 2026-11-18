<?php
// an implicitly nullable parameter (`T $x = null`) of a union type gains
// |null, and of an intersection becomes the DNF type (A&B)|null
interface X {} interface Y {}
class XY implements X, Y {}
function foo(X&Y $foo = null) { var_dump($foo); }
function bar(int|string $a = null) { var_dump($a); }
function baz(X $a = null) {}
foreach (["foo","bar","baz"] as $f) echo (new ReflectionFunction($f))->getParameters()[0]->getType(), "\n";
foo(null); foo(new XY); bar(null); bar(5);
try { foo(new stdClass); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
echo str_replace(__FILE__, "FILE", (string) new ReflectionFunction("foo"));
