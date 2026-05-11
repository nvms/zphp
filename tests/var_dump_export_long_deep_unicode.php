<?php
var_dump(1);
var_dump(-1);
var_dump(0);
var_dump(PHP_INT_MAX);
var_dump(PHP_INT_MIN);

var_dump(1.5);
var_dump(-3.14);
var_dump(0.0);
var_dump(1e10);
var_dump(1e-10);

var_dump("hello");
var_dump("");
var_dump("with\ttabs\nand\nnewlines");
var_dump("with\"quotes");

var_dump(true);
var_dump(false);
var_dump(null);

var_dump([1, 2, 3]);
var_dump(["a" => 1, "b" => 2]);
var_dump([]);
var_dump([1, "x", 1.5, true, null]);

var_dump(["nested" => ["deep" => ["deeper" => "leaf"]]]);

var_dump([
    "users" => [
        ["name" => "alice", "age" => 30],
        ["name" => "bob", "age" => 25],
    ],
]);

$long = str_repeat("x", 100);
var_dump($long);

$arr = [];
for ($i = 0; $i < 10; $i++) $arr[] = $i;
var_dump($arr);

$nested = ["level" => 0, "next" => ["level" => 1, "next" => ["level" => 2, "next" => []]]];
print_r($nested);

var_dump((object)["a" => 1, "b" => "two"]);

class Box {
    public int $val = 42;
    private string $secret = "hidden";
}

var_dump(new Box);

class Container {
    public array $items = [1, 2, 3];
    public ?stdClass $meta = null;
}
var_dump(new Container);

var_dump([true, false, null, INF, -INF, NAN]);

var_dump([1, [2, [3, [4]]]]);

var_dump("naïve");
var_dump("日本語");

$tmp = sys_get_temp_dir() . "/_zphp_dump3_probe.txt";
file_put_contents($tmp, "test");
$h = fopen($tmp, "r");
var_dump(get_resource_type($h));
fclose($h);
unlink($tmp);

var_dump(["string" => "hello world", "number" => 42, "float" => 3.14]);

$big = array_fill(0, 50, "x");
echo count($big), "\n";

var_dump(range(1, 5));

class WithMagic {
    public int $a = 1;
    public function __debugInfo(): array {
        return ["a" => $this->a, "computed" => $this->a * 10];
    }
}
var_dump(new WithMagic);

echo str_repeat("=", 50), "\n";

$arr = [
    "name" => "config",
    "version" => "1.0",
    "settings" => [
        "debug" => true,
        "log_level" => 3,
        "outputs" => ["stdout", "file"],
    ],
    "modules" => [
        "auth" => ["enabled" => true, "type" => "oauth"],
        "cache" => ["enabled" => false],
    ],
];
print_r($arr);
echo str_repeat("=", 50), "\n";
var_dump($arr);

echo strlen(var_export("hello", true)), "\n";
echo var_export([1, 2, 3], true), "\n";

$json = json_encode(["a" => 1, "b" => [2, 3]]);
echo $json, "\n";

echo var_export(true, true), "\n";
echo var_export(false, true), "\n";
echo var_export(null, true), "\n";
echo var_export(0, true), "\n";
echo var_export(3.14, true), "\n";
echo var_export("hi", true), "\n";
echo var_export([], true), "\n";
echo var_export(["a" => 1], true), "\n";

class Simple {
    public int $x = 10;
}
echo var_export(new Simple, true), "\n";

var_dump(new stdClass);

$arr = ["k1" => 1, "k2" => "string", "k3" => true, "k4" => null];
var_dump($arr);
