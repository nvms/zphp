<?php
// the next integer key and lookups of integer keys after operations that
// renumber or add keys directly
$a = [1, 2, 3];
array_shift($a);
$a[] = 9;
var_dump($a);
$b = ['x' => 1];
array_unshift($b, 'u');
var_dump(isset($b[0]), $b[0]);
$b[] = 'next';
var_dump($b);
$c = [] + [5 => 'five', 'k' => 'v'];
var_dump(isset($c[5]), $c[5]);
$c[] = 'six';
var_dump($c);
$d = [-5 => 'a'];
$d[] = 'b';
array_pop($d);
$d[] = 'c';
var_dump($d, isset($d[-5]), isset($d[100]));
$big = range(0, 2999);
$m = array_map(fn ($x) => $x + 1, $big);
var_dump(count($m), $m[2999], isset($m[3000]));
$s = new SplDoublyLinkedList;
$s->unshift('a');
$s->add(1, 'b');
var_dump($s->offsetGet(0), $s->offsetGet(1));
$q = new SplPriorityQueue;
$q->insert('lo', 1);
$q->insert('hi', 2);
var_dump($q->extract(), $q->count());
$m = [PHP_INT_MAX => 1]; $m[PHP_INT_MAX] = 2; $m[(string) PHP_INT_MAX] = 3; var_dump($m, isset($m[PHP_INT_MAX]));
