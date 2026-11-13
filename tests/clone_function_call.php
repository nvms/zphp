<?php
class P { public $a = 1; public readonly int $r; function __construct() { $this->r = 5; } function __clone() { echo "__clone\n"; } }
$p = new P;
var_dump(clone(object: $p, withProperties: ['a' => 2]));
var_dump(clone($p, withProperties: ['a' => 3]));
var_dump(clone(...[$p, ['a' => 4]]));
var_dump(clone(...['object' => $p]));
$f = clone(...);
var_dump($f);
var_dump($f($p, ['a' => 5]));
var_dump(array_map(clone(...), [new stdClass, new stdClass]));
try { clone($p, [], 1); } catch (ArgumentCountError $e) { echo $e->getMessage(), "\n"; }
try { clone(); } catch (ArgumentCountError $e) { echo $e->getMessage(), "\n"; }
try { clone(objekt: $p); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { clone(...[1]); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { clone($p, withProperties: 1); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { $f($p, ['r' => 9]); } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump(call_user_func('clone', $p, ['a' => 6])->a);
var_dump(function_exists('clone'));
echo new ReflectionFunction('clone');
class Priv { private function __clone() {} static function make($o) { return clone(...[$o]); } }
var_dump(Priv::make(new Priv));
try { clone(...[new Priv]); } catch (Error $e) { echo $e->getMessage(), "\n"; }
