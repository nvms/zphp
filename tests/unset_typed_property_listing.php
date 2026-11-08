<?php
// var_dump lists a typed property that was unset as uninitialized, as it does
// one never assigned; the other listings leave it out
class T { public int $a = 1; public ?string $b = "x"; public $c = 2; private array $d = []; }
$t = new T();
unset($t->a, $t->b, $t->c);
var_dump($t);
print_r($t); echo "\n";
var_dump((array)$t, get_object_vars($t));
