<?php
// SplFixedArray lists its elements, then its property table as it is: a
// dynamic property "0" stays a string key beside element 0, and an
// uninitialized typed property has no entry

#[AllowDynamicProperties]
class MySplFixedArray extends SplFixedArray
{
    public $x;
    public int $y;
}
class X {}
class Y {}

$array = new MySplFixedArray(2);
var_dump(get_mangled_object_vars($array));
$array[0] = new stdClass();
$array[1] = new Y();
$array->x = new SplFixedArray();
$array->{0} = new X();
var_dump($array);
var_dump(get_mangled_object_vars($array));
var_dump((array) $array);
echo json_encode($array), "\n";
$ser = serialize($array);
echo "$ser\n";
var_dump(unserialize($ser));
print_r($array);
echo "\n";

$plain = new MySplFixedArray(1);
$plain->y = 5;
var_dump($plain, serialize($plain), unserialize(serialize($plain)));
