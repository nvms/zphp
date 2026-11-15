<?php
// Exception::__toString keeps its result in the base class's private $string
class E extends Exception {}
$e = new E("m", 1, new Error("inner"));
$s = (string) $e;
var_dump(strlen($s) > 0);
$r = new ReflectionProperty(Exception::class, "string"); var_dump($r->getValue($e) === $s);
$p = $e->getPrevious(); $r2 = new ReflectionProperty(Error::class, "string"); var_dump($r2->getValue($p));
$err = new TypeError("t"); (string) $err; var_dump(strlen($r2->getValue($err)) > 0);
