<?php
// a resource against a string compares both as numbers; an object is
// greater than a resource
$r = fopen('php://memory', 'r');
$id = (int) $r;
$values = ['str' => 'str', 'empty' => '', 'zero' => '0', 'id' => (string) $id, 'id+1' => (string) ($id + 1), '1e9' => '1e9', 'space3' => ' 3', 'stdClass' => new stdClass, 'ArrayObject' => new ArrayObject([])];
foreach ($values as $shown => $v) {
    echo $shown, ": ", $r <=> $v, " ", $v <=> $r, " ", var_export($r == $v, true), " ", var_export($r < $v, true), " ", var_export($v > $r, true), "\n";
}
$list = ['b', $r, 'a'];
sort($list);
var_dump(array_map('gettype', $list));
