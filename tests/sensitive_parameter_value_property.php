<?php
// SensitiveParameterValue keeps its value in the private readonly $value
// its stub declares, which no listing shows
$v = new SensitiveParameterValue('secret');
$p = (new ReflectionClass($v))->getProperty('value');
var_dump($p->getValue($v), $p->isReadOnly(), $p->isPrivate(), (string) $p->getType(), $v->getValue());
var_dump($v);
print_r($v);
echo "\n";
var_dump((array) $v);
try {
    $v->value = 1;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
function f(#[SensitiveParameter] $x) { return debug_backtrace()[0]['args'][0]; }
$o = f('pw');
var_dump($o->getValue(), (new ReflectionProperty($o, 'value'))->getValue($o));
