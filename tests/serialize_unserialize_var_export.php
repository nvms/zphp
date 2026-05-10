<?php
echo serialize(42), "\n";
echo serialize(3.14), "\n";
echo serialize("hello"), "\n";
echo serialize(true), "\n";
echo serialize(null), "\n";
echo serialize([1, 2, 3]), "\n";
echo serialize(["a" => 1, "b" => 2]), "\n";
echo serialize([1, "x", true, null, 1.5]), "\n";
echo serialize([]), "\n";

$nested = ["a" => ["b" => ["c" => "deep"]]];
echo serialize($nested), "\n";

class Point {
    public int $x = 1;
    public int $y = 2;
}
$p = new Point;
echo serialize($p), "\n";

class Box {
    public int $size = 5;
    public Point $origin;
    public function __construct() { $this->origin = new Point; }
}
echo serialize(new Box), "\n";

var_dump(unserialize('i:42;'));
var_dump(unserialize('s:5:"hello";'));
var_dump(unserialize('b:1;'));
var_dump(unserialize('N;'));
var_dump(unserialize('a:2:{i:0;i:1;i:1;i:2;}'));

$round = unserialize(serialize(["a" => 1, "b" => [2, 3], "c" => "str"]));
print_r($round);

$o = unserialize(serialize(new Point));
echo get_class($o), " x=", $o->x, " y=", $o->y, "\n";

$arr = unserialize(serialize([
    new Point,
    new Point,
    "literal",
]));
echo count($arr), " ", get_class($arr[0]), " ", $arr[2], "\n";

// allowed_classes
$s = serialize(new Point);
$r = unserialize($s, ["allowed_classes" => false]);
echo get_class($r), "\n"; // __PHP_Incomplete_Class

$r = unserialize($s, ["allowed_classes" => ["Point"]]);
echo get_class($r), "\n"; // Point

$r = unserialize($s, ["allowed_classes" => ["Other"]]);
echo get_class($r), "\n"; // __PHP_Incomplete_Class

$r = unserialize($s, ["allowed_classes" => true]);
echo get_class($r), "\n"; // Point

// circular references via array reference
$a = [];
$a[] = 1;
$a[] = &$a;
$ser = serialize($a);
echo strlen($ser) > 0 ? "ser-ok " : "ser-fail ", "\n";

// var_export
var_export(42);
echo "\n";
var_export(3.14);
echo "\n";
var_export("hello");
echo "\n";
var_export("with 'quote'");
echo "\n";
var_export(true);
echo "\n";
var_export(false);
echo "\n";
var_export(null);
echo "\n";
var_export([1, 2, 3]);
echo "\n";
var_export(["a" => 1, "b" => 2]);
echo "\n";
var_export(["a" => ["b" => ["c" => 1]]]);
echo "\n";

echo var_export(["x" => 1], true), "\n";

// var_export round-trip via eval (architectural - eval not implemented)

// var_export indentation
var_export([
    "k1" => "v1",
    "nested" => [
        "x" => 1,
        "y" => 2,
    ],
    "list" => [1, 2, 3],
]);
echo "\n";

// var_export object
class Cfg {
    public string $name = "alpha";
    public int $level = 7;
}
var_export(new Cfg);
echo "\n";

// var_export object roundtrip via __set_state
class Info {
    public string $a = "x";
    public int $b = 0;
    public static function __set_state(array $arr): self {
        $i = new self;
        $i->a = $arr["a"];
        $i->b = $arr["b"];
        return $i;
    }
}
// __set_state eval round-trip (architectural - eval not implemented)

// json round trip basic
echo json_encode(["a" => 1, "b" => [1, 2, 3]]), "\n";
print_r(json_decode('{"a":1,"b":[1,2,3]}', true));

// print_r return
$out = print_r(["a" => 1], true);
echo strlen($out) > 0 ? "ok\n" : "fail\n";
echo $out;
