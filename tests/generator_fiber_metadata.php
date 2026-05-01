<?php

// Generator should be recognized as an object by is_object() and method_exists()
function gen() { yield 1; yield 2; }
$g = gen();

var_dump(is_object($g));
var_dump(get_class($g));
var_dump(method_exists($g, 'current'));
var_dump(method_exists($g, 'send'));
var_dump(method_exists($g, 'throw'));
var_dump(method_exists($g, 'nonexistent'));
var_dump(method_exists('Generator', 'next'));

// Fiber metadata
$f = new Fiber(function () { Fiber::suspend(); });
var_dump(is_object($f));
var_dump(get_class($f));
var_dump($f instanceof Fiber);
var_dump(method_exists($f, 'start'));
var_dump(method_exists($f, 'resume'));
var_dump(method_exists('Fiber', 'getCurrent'));

// ReflectionFunction::isGenerator
function plainFn() {}
function genFn() { yield 1; }
var_dump((new ReflectionFunction('plainFn'))->isGenerator());
var_dump((new ReflectionFunction('genFn'))->isGenerator());
