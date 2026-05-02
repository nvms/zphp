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

// is_a / is_subclass_of
var_dump(is_a($g, 'Generator'));
var_dump(is_a($g, 'Iterator'));
var_dump(is_a($g, 'Traversable'));
var_dump(is_subclass_of($g, 'Iterator'));
var_dump(is_subclass_of($g, 'Generator'));
var_dump(is_a($f, 'Fiber'));

// get_class_methods
$gm = get_class_methods($g);
echo "gen methods: " . implode(',', $gm) . "\n";
$fm = get_class_methods('Fiber');
echo "fiber methods: " . implode(',', $fm) . "\n";

// spl_object_hash returns 32-char hex string for any of these
var_dump(strlen(spl_object_hash($g)) === 32);
var_dump(strlen(spl_object_hash($f)) === 32);
