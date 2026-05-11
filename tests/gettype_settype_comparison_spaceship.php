<?php
echo gettype(1), "\n";
echo gettype(1.5), "\n";
echo gettype("hello"), "\n";
echo gettype(true), "\n";
echo gettype(null), "\n";
echo gettype([]), "\n";
echo gettype([1,2,3]), "\n";
echo gettype(new stdClass), "\n";

$v = 5;
settype($v, "string");
var_dump($v);

$v = "42";
settype($v, "int");
var_dump($v);

$v = "3.14";
settype($v, "float");
var_dump($v);

$v = 0;
settype($v, "bool");
var_dump($v);

$v = 1;
settype($v, "bool");
var_dump($v);

$v = "0";
settype($v, "bool");
var_dump($v);

$v = "0.0";
settype($v, "bool");
var_dump($v);

$v = "false";
settype($v, "bool");
var_dump($v);

$v = "";
settype($v, "bool");
var_dump($v);

echo (1 < 2) ? "y" : "n", "\n";
echo (1 < 1) ? "y" : "n", "\n";
echo (1 <= 1) ? "y" : "n", "\n";
echo (1 > 0) ? "y" : "n", "\n";
echo (1 >= 1) ? "y" : "n", "\n";

echo "abc" < "abd" ? "y" : "n", "\n";
echo "abc" < "abc" ? "y" : "n", "\n";
echo "abc" == "abc" ? "y" : "n", "\n";

echo 1 == "1" ? "y" : "n", "\n";
echo 1 === "1" ? "y" : "n", "\n";
echo 1 == 1.0 ? "y" : "n", "\n";
echo 1 === 1.0 ? "y" : "n", "\n";

echo 0 == false ? "y" : "n", "\n";
echo 0 === false ? "y" : "n", "\n";
echo null == 0 ? "y" : "n", "\n";
echo null === 0 ? "y" : "n", "\n";
echo null == "" ? "y" : "n", "\n";
echo null == false ? "y" : "n", "\n";
echo null === null ? "y" : "n", "\n";

echo "" == false ? "y" : "n", "\n";
echo "0" == false ? "y" : "n", "\n";
echo "0" == 0 ? "y" : "n", "\n";

echo 1 <=> 2, "\n";
echo 2 <=> 1, "\n";
echo 1 <=> 1, "\n";
echo "a" <=> "b", "\n";
echo "b" <=> "a", "\n";
echo "a" <=> "a", "\n";
echo [1, 2] <=> [1, 3], "\n";
echo [1, 2] <=> [1, 2], "\n";
echo [1, 2, 3] <=> [1, 2], "\n";

echo [1, 2] == [1, 2] ? "y" : "n", "\n";
echo [1, 2] === [1, 2] ? "y" : "n", "\n";
echo ["a"=>1, "b"=>2] == ["b"=>2, "a"=>1] ? "y" : "n", "\n";
echo ["a"=>1, "b"=>2] === ["b"=>2, "a"=>1] ? "y" : "n", "\n";

echo "10" < "9" ? "y" : "n", "\n";
echo (int)"10" < (int)"9" ? "y" : "n", "\n";

echo 100 == 100.0 ? "y" : "n", "\n";
echo 100 === 100.0 ? "y" : "n", "\n";

$obj1 = new stdClass;
$obj1->x = 1;
$obj2 = new stdClass;
$obj2->x = 1;
$obj3 = $obj1;

echo $obj1 == $obj2 ? "y" : "n", "\n";
echo $obj1 === $obj2 ? "y" : "n", "\n";
echo $obj1 === $obj3 ? "y" : "n", "\n";

echo gettype((int)"42"), "\n";
echo gettype((float)"3.14"), "\n";
echo gettype((string)42), "\n";
echo gettype((bool)1), "\n";
echo gettype((array)"x"), "\n";

$arr = ["a" => 1];
settype($arr, "object");
echo gettype($arr), "\n";
echo $arr->a ?? "null", "\n";

$obj = (object)["a" => 1, "b" => 2];
settype($obj, "array");
echo gettype($obj), "\n";
print_r($obj);

echo 1 <=> "1.0", "\n";
echo "1" <=> 1, "\n";

echo "abc" == 0 ? "y" : "n", "\n";

echo PHP_INT_MAX == PHP_INT_MAX + 0.0 ? "y" : "n", "\n";

echo gettype("123" + 1), "\n";
echo gettype("1.5" + 1), "\n";

var_dump(1 == "01");
var_dump(10 == "1e1");
var_dump(100 == "1e2");

echo 0 <=> "a", "\n";
echo "a" <=> 0, "\n";

class Box {
    public function __construct(public int $v) {}
}

$a = new Box(1);
$b = new Box(1);
$c = new Box(2);
echo $a == $b ? "y" : "n", "\n";
echo $a === $b ? "y" : "n", "\n";
echo $a == $c ? "y" : "n", "\n";

echo PHP_INT_MAX === PHP_INT_MAX ? "y" : "n", "\n";

$arr1 = ["k" => 1, 0 => 2];
$arr2 = [0 => 2, "k" => 1];
echo $arr1 == $arr2 ? "y" : "n", "\n";
echo $arr1 === $arr2 ? "y" : "n", "\n";

echo true <=> false, "\n";
echo false <=> true, "\n";

$test = [3, 1, 4, 1, 5, 9, 2];
usort($test, fn($a, $b) => $a <=> $b);
print_r($test);
