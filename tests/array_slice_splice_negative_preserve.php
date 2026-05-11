<?php
print_r(array_slice([1,2,3,4,5], 2));
print_r(array_slice([1,2,3,4,5], 1, 2));
print_r(array_slice([1,2,3,4,5], -2));
print_r(array_slice([1,2,3,4,5], -3, 2));
print_r(array_slice([1,2,3,4,5], 0, -2));
print_r(array_slice([1,2,3,4,5], -3, -1));
print_r(array_slice([1,2,3,4,5], 2, 10));
print_r(array_slice([1,2,3,4,5], 10));
print_r(array_slice([1,2,3,4,5], 0));
print_r(array_slice([1,2,3,4,5], 0, 0));

print_r(array_slice(["a"=>1,"b"=>2,"c"=>3,"d"=>4], 1));
print_r(array_slice(["a"=>1,"b"=>2,"c"=>3,"d"=>4], 1, 2));
print_r(array_slice(["a"=>1,"b"=>2,"c"=>3,"d"=>4], -2));
print_r(array_slice(["a"=>1,"b"=>2,"c"=>3,"d"=>4], 1, null, true));

print_r(array_slice([10,20,30,40,50], 1, 3, true));
print_r(array_slice([10,20,30,40,50], 1, 3, false));

print_r(array_slice([], 0));
print_r(array_slice([], -2));
print_r(array_slice([1], 0));
print_r(array_slice([1], 0, 0));
print_r(array_slice([1], -10));
print_r(array_slice([1,2,3], 1, null));

$arr = [1,2,3,4,5];
$removed = array_splice($arr, 2);
print_r($arr);
print_r($removed);

$arr = [1,2,3,4,5];
$removed = array_splice($arr, 1, 2);
print_r($arr);
print_r($removed);

$arr = [1,2,3,4,5];
$removed = array_splice($arr, 1, 2, [99, 100]);
print_r($arr);
print_r($removed);

$arr = [1,2,3,4,5];
$removed = array_splice($arr, 0, 0, [0]);
print_r($arr);
print_r($removed);

$arr = [1,2,3,4,5];
$removed = array_splice($arr, -2, 1);
print_r($arr);
print_r($removed);

$arr = [1,2,3,4,5];
$removed = array_splice($arr, -3, -1);
print_r($arr);
print_r($removed);

$arr = [1,2,3,4,5];
$removed = array_splice($arr, 2, 1, "single");
print_r($arr);
print_r($removed);

$arr = ["a"=>1,"b"=>2,"c"=>3];
$removed = array_splice($arr, 1, 1);
print_r($arr);
print_r($removed);

$arr = ["a"=>1,"b"=>2,"c"=>3];
$removed = array_splice($arr, 1, 1, ["x"=>99]);
print_r($arr);
print_r($removed);

$arr = [1,2,3];
$removed = array_splice($arr, 0, count($arr));
print_r($arr);
print_r($removed);

$arr = [];
$removed = array_splice($arr, 0, 0, [1, 2, 3]);
print_r($arr);
print_r($removed);

$arr = [1,2,3];
$removed = array_splice($arr, 1, 0, [10, 20]);
print_r($arr);
print_r($removed);

$arr = [1,2,3,4];
$removed = array_splice($arr, 5);
print_r($arr);
print_r($removed);

$arr = [1,2,3,4];
$removed = array_splice($arr, -10);
print_r($arr);
print_r($removed);

print_r(array_slice([1,2,3,4,5], 0, -1));
print_r(array_slice([1,2,3,4,5], 1, -1));
print_r(array_slice([1,2,3,4,5], -4, -2));

print_r(array_slice([1,2,3], 100));
print_r(array_slice([1,2,3], 0, 100));

$big = range(1, 20);
print_r(array_slice($big, 5, 5));
print_r(array_slice($big, -10, 5));

$arr = [10, 20, 30];
$removed = array_splice($arr, 1);
print_r($arr);
print_r($removed);

$arr = [10, 20, 30];
$removed = array_splice($arr, 1, 0);
print_r($arr);
print_r($removed);

$arr = [10, 20, 30];
$removed = array_splice($arr, 0, 3);
print_r($arr);
print_r($removed);

$arr = [10, 20, 30];
$removed = array_splice($arr, 1, 1, []);
print_r($arr);
print_r($removed);
