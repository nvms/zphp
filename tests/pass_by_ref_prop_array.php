<?php
// covers: pass-by-reference for $obj->prop['key'] combined access

function modify_ref(&$val) {
    $val = 'changed';
}

function swap_refs(&$a, &$b) {
    $tmp = $a;
    $a = $b;
    $b = $tmp;
}

// string key
$obj = new stdClass();
$obj->items = ['key' => 'original'];
modify_ref($obj->items['key']);
echo $obj->items['key'] . "\n"; // changed

// int key
$obj2 = new stdClass();
$obj2->data = [10, 20, 30];
modify_ref($obj2->data[1]);
echo $obj2->data[1] . "\n"; // changed

// variable key
$obj3 = new stdClass();
$obj3->map = ['x' => 'before'];
$k = 'x';
modify_ref($obj3->map[$k]);
echo $obj3->map['x'] . "\n"; // changed

// swap between prop-array ref and simple ref
$obj4 = new stdClass();
$obj4->arr = ['a' => 'from_obj'];
$plain = 'from_plain';
swap_refs($obj4->arr['a'], $plain);
echo $obj4->arr['a'] . "\n"; // from_plain
echo $plain . "\n"; // from_obj

// nested array in property
$obj5 = new stdClass();
$obj5->nested = ['outer' => ['inner' => 'deep']];
modify_ref($obj5->nested['outer']);
echo $obj5->nested['outer'] . "\n"; // changed

// numeric string key
$obj6 = new stdClass();
$obj6->items = ['0' => 'zero', '1' => 'one'];
modify_ref($obj6->items['0']);
echo $obj6->items['0'] . "\n"; // changed

echo "ALL TESTS PASSED\n";
