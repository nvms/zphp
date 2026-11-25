<?php
// `f()[k]++` steps an element of the call's result, a copy: the array the
// function returned by value is left alone; one returned by reference is
// written through
class Foo {
    public $a = [1, 'n' => 5];
    public function byValue() { return $this->a; }
    public function &byRef() { return $this->a; }
}
function values() { static $s = [10]; return $s; }

$foo = new Foo;
$foo->byValue()[0]++;
++$foo->byValue()[0];
$foo->byValue()['n']--;
--$foo->byValue()['n'];
var_dump($foo->a);
$foo->byRef()[0]++;
--$foo->byRef()['n'];
var_dump($foo->a);
var_dump(values()[0]++, values()[0]);
$copy = $foo->byValue();
$copy[0]++;
var_dump($copy[0], $foo->a[0]);
for ($i = 0; $i < 3; $i++) {
    $foo->byValue()[0]++;
    $copy[0]++;
}
var_dump($copy[0], $foo->a[0]);
