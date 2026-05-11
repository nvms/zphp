<?php
$arr = [1, 2, ["a", "b", ["x", "y"]], 3];
print_r($arr);

print_r([[[[1]]]]);

$nested = [
    "a" => ["b" => ["c" => ["d" => "deep"]]],
    "list" => [1, 2, [3, 4]],
];
print_r($nested);

echo var_export($arr, true), "\n";
echo var_export($nested, true), "\n";

var_dump($arr);
var_dump($nested);

class Box {
    public int $pub = 1;
    protected int $prot = 2;
    private int $priv = 3;
}

$b = new Box;
print_r($b);
echo "---\n";
var_dump($b);
echo "---\n";
echo var_export($b, true), "\n";

class Child extends Box {
    public int $childPub = 10;
    private int $childPriv = 20;
}
$c = new Child;
print_r($c);
echo "---\n";
var_dump($c);

class Container {
    public array $items = [];
    public ?Container $parent = null;
}
$root = new Container;
$child = new Container;
$child->parent = $root;
$root->items[] = $child;

var_dump($root);
echo "---\n";
print_r($root);

class WithObj {
    public ?stdClass $obj = null;
}

$o = new WithObj;
$o->obj = new stdClass;
$o->obj->x = 42;
var_dump($o);
print_r($o);

$o = (object)["a" => 1, "b" => "two", "c" => [1, 2, 3]];
var_dump($o);
print_r($o);
echo var_export($o, true), "\n";

print_r([]);
var_dump([]);
echo var_export([], true), "\n";

print_r(new stdClass);
echo var_export(new stdClass, true), "\n";

$arr = ["k" => "v"];
print_r($arr);
var_dump($arr);

print_r(["", " ", "\t", "\n"]);

print_r(["int" => 42, "float" => 3.14, "bool" => true, "null" => null, "str" => "hello"]);
var_dump(["int" => 42, "float" => 3.14, "bool" => true, "null" => null, "str" => "hello"]);

$arr = [];
$arr["self"] = &$arr;
print_r($arr);

class CircularA {
    public ?CircularB $b = null;
}
class CircularB {
    public ?CircularA $a = null;
}
$a = new CircularA;
$b = new CircularB;
$a->b = $b;
$b->a = $a;
print_r($a);

class Owner {
    public string $name;
    public array $children = [];
    public function __construct(string $n) { $this->name = $n; }
}

$root = new Owner("root");
$root->children[] = new Owner("a");
$root->children[] = new Owner("b");
$root->children[0]->children[] = new Owner("a1");
$root->children[0]->children[] = new Owner("a2");
print_r($root);

print_r(["list" => [1, 2, 3], "obj" => (object)["x" => 1]]);

echo "[", var_export(["a", "b"], true), "]\n";
echo "[", var_export(42, true), "]\n";
echo "[", var_export("hello", true), "]\n";
echo "[", var_export(true, true), "]\n";
echo "[", var_export(null, true), "]\n";
echo "[", var_export(3.14, true), "]\n";
echo "[", var_export(["x" => 1, "y" => "two"], true), "]\n";

class Deep {
    public ?Deep $next = null;
}
$d = new Deep;
$d->next = new Deep;
$d->next->next = new Deep;
$d->next->next->next = new Deep;
print_r($d);
