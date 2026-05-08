<?php
// stdClass preserves insertion order
$o = new stdClass;
$o->z = 1;
$o->y = 2;
$o->x = 3;
print_r($o);

// (object) cast preserves array order
$o2 = (object)['a' => 1, 'b' => 2, 'c' => 3];
print_r($o2);

// foreach iterates in insertion order
$o3 = new stdClass;
foreach (['third', 'first', 'second'] as $k) $o3->{$k} = $k;
foreach ($o3 as $k => $v) echo "$k=$v\n";

// json_encode reflects insertion order
$o4 = new stdClass;
$o4->b = 2; $o4->a = 1; $o4->c = 3;
echo json_encode($o4), "\n";

// unset preserves order of remaining
$o5 = new stdClass;
$o5->a = 1; $o5->b = 2; $o5->c = 3; $o5->d = 4;
unset($o5->b);
print_r($o5);

// array_column over objects
$rows = [
    (object)['id' => 1, 'name' => 'alpha'],
    (object)['id' => 2, 'name' => 'beta'],
    (object)['id' => 3, 'name' => 'gamma'],
];
print_r(array_column($rows, 'name'));
print_r(array_column($rows, 'name', 'id'));
print_r(array_column($rows, null, 'id'));
