<?php
// the right side of instanceof is a class name, or any expression in
// parentheses (or a variable) whose value names the class
$class = 'Class';
$obj = new stdClass;
var_dump($obj instanceof ('std' . $class));
var_dump($obj instanceof ('Array' . 'Object'));
var_dump(new ArrayObject instanceof ('Array' . 'Object'));
var_dump($obj instanceof stdClass, $obj instanceof Traversable);
$names = ['std' => 'stdClass'];
var_dump($obj instanceof $names['std']);
var_dump($obj instanceof ($names['std']));
var_dump($obj instanceof ($obj));
function name() { return 'stdClass'; }
var_dump($obj instanceof (name()));
