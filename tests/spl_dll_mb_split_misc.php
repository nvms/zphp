<?php
// SplDoublyLinkedList add (insert at offset)
$l = new SplDoublyLinkedList();
$l->push(1); $l->push(2); $l->push(4);
$l->add(2, 3); // insert 3 at offset 2
foreach ($l as $v) echo "$v ";
echo "\n";

// serialize/unserialize SplDoublyLinkedList
$l2 = new SplDoublyLinkedList();
$l2->push("a"); $l2->push("b"); $l2->push("c");
$s = serialize($l2);
$r = unserialize($s);
foreach ($r as $v) echo "$v ";
echo "\n";

// array_walk_recursive on objects nested in arrays - PHP doesn't recurse into objects
$arr = ["x" => 1, "obj" => new stdClass(), "y" => ["z" => 2]];
$arr["obj"]->p = 99;
array_walk_recursive($arr, function (&$v, $k) { if (is_int($v)) $v = $v * 10; });
echo $arr["x"], "|", $arr["obj"]->p, "|", $arr["y"]["z"], "\n";

// mb_str_split (PHP 8.0+)
print_r(mb_str_split("hello", 2));
print_r(mb_str_split("héllo", 2));
print_r(mb_str_split("世界你好", 2));
print_r(mb_str_split(""));

// iterator_to_array preserve_keys
function gen3() { yield "a" => 1; yield "a" => 2; yield "b" => 3; }
print_r(iterator_to_array(gen3())); // last "a" wins
print_r(iterator_to_array(gen3(), false)); // numeric reindex

// SORT_NATURAL + FLAG_CASE
$arr = ["IMG10", "img1", "Img2", "img20"];
sort($arr, SORT_NATURAL | SORT_FLAG_CASE);
print_r($arr);

// spl_autoload_register
spl_autoload_register(function ($cls) {
    echo "loading:$cls\n";
    eval("class $cls {}"); // can't, but...
});
// won't actually load, just check registration succeeds
$fns = spl_autoload_functions();
echo count($fns) > 0 ? "registered\n" : "no\n";

// ReflectionClass methods
class Sample {
    public function pubA() {}
    protected function protB() {}
    private function privC() {}
    public static function statD() {}
}
$rc = new ReflectionClass(Sample::class);
foreach ($rc->getMethods(ReflectionMethod::IS_PUBLIC) as $m) echo $m->name, " ";
echo "|\n";
foreach ($rc->getMethods(ReflectionMethod::IS_STATIC) as $m) echo $m->name, " ";
echo "|\n";
foreach ($rc->getMethods(ReflectionMethod::IS_PROTECTED) as $m) echo $m->name, " ";
echo "|\n";

// ReflectionParameter::getDefaultValue
function withDef(int $a, string $b = "hello", array $c = [1,2,3], ?int $d = null): void {}
$rf = new ReflectionFunction('withDef');
foreach ($rf->getParameters() as $p) {
    if ($p->isDefaultValueAvailable()) {
        echo $p->getName(), "=";
        var_export($p->getDefaultValue());
        echo "\n";
    } else {
        echo $p->getName(), "=<no default>\n";
    }
}

// nested generators with keys
function inner() { yield "k1" => 10; yield "k2" => 20; }
function outer() { yield "x" => 1; yield from inner(); yield "y" => 2; }
foreach (outer() as $k => $v) echo "$k=$v ";
echo "\n";

// array deep clone semantics with nested objects
$obj = new stdClass; $obj->n = 1;
$a = ["arr" => [1, 2], "obj" => $obj];
$b = $a; // copy-on-assign for array; obj is shared (PHP)
$b["arr"][] = 3; // doesn't affect $a
$b["obj"]->n = 99; // does affect $a (object semantics)
echo count($a["arr"]), "|", $a["obj"]->n, "\n";

// nested array modification
$a = ["x" => [1, 2]];
$b = $a;
$b["x"][0] = 100;
echo $a["x"][0], "|", $b["x"][0], "\n"; // 1|100

// string concat vs interp
$x = 42;
echo "x=$x|", "x=" . $x . "\n";

// preg_match_all match-by-set
$re = '/(\d+)-(\w+)/';
preg_match_all($re, "1-apple 2-banana 3-cherry", $m, PREG_SET_ORDER);
foreach ($m as $set) echo "$set[1]:$set[2]|";
echo "\n";

// __destruct skipped (no per-object destruction in zphp)

// clone + __clone
class WithRef {
    public array $data;
    public function __construct() { $this->data = [1,2,3]; }
    public function __clone(): void { echo "cloned\n"; $this->data[] = 99; }
}
$w = new WithRef;
$c = clone $w;
print_r($c->data);

// final classes/methods
final class FinalClass { public function f() { return 1; } }
class Base2 { final public function locked() { return 1; } }
echo (new FinalClass)->f(), "\n";
echo (new Base2)->locked(), "\n";

// static class vars
class Counter { public static int $n = 0; public static function inc(): void { self::$n++; } }
Counter::inc(); Counter::inc(); Counter::inc();
echo Counter::$n, "\n";
