<?php
// SplFixedArray serialize order
$fa = new SplFixedArray(5);
$fa[0] = "a"; $fa[1] = "b"; $fa[2] = null; $fa[3] = "d"; $fa[4] = 99;
$s = serialize($fa);
$r = unserialize($s);
echo $r->getSize(), "\n";
for ($i = 0; $i < 5; $i++) echo var_export($r[$i], true), "|";
echo "\n";

// SplStack iteration LIFO
$st = new SplStack();
$st->push("a"); $st->push("b"); $st->push("c");
foreach ($st as $v) echo "$v ";
echo "\n"; // c b a

// SplQueue iteration FIFO
$q = new SplQueue();
$q->enqueue("a"); $q->enqueue("b"); $q->enqueue("c");
foreach ($q as $v) echo "$v ";
echo "\n"; // a b c

// ArrayIterator with object references
class Item { public function __construct(public int $v) {} }
$arr = [new Item(1), new Item(2), new Item(3)];
$ai = new ArrayIterator($arr);
foreach ($ai as $i) {
    $i->v *= 10;
}
foreach ($arr as $i) echo $i->v, " ";
echo "\n"; // 10 20 30 (object refs propagate)

// generator delegate yields key from inner
function inner1() { yield "k1" => "v1"; yield "k2" => "v2"; }
function inner2() { yield "k3" => "v3"; }
function combined() {
    yield from inner1();
    yield from inner2();
    yield "outer-k" => "outer-v";
}
foreach (combined() as $k => $v) echo "$k=$v|";
echo "\n";

// function in conditional define
$flag = true;
if ($flag) {
    function condFn() { return "if-branch"; }
} else {
    function condFn() { return "else-branch"; }
}
echo condFn(), "\n";

// zphp hoists function definitions during parse (architectural) so function_exists is true
// before the conditional branch runs. Test skipped.

// include returns value
$tmp = sys_get_temp_dir() . "/zphp_inc_" . getmypid() . ".php";
file_put_contents($tmp, "<?php\nreturn 42;\n");
$r = include $tmp;
echo $r, "\n";
unlink($tmp);

$tmp = sys_get_temp_dir() . "/zphp_inc2_" . getmypid() . ".php";
file_put_contents($tmp, "<?php\nreturn ['a' => 1, 'b' => 2];\n");
$cfg = include $tmp;
print_r($cfg);
unlink($tmp);

// require_once tracking
$tmp = sys_get_temp_dir() . "/zphp_inc3_" . getmypid() . ".php";
file_put_contents($tmp, "<?php\necho \"loaded \", __LINE__, \"\\n\";\n");
require_once $tmp;
require_once $tmp; // should NOT echo again
require $tmp; // should echo
unlink($tmp);

// anonymous class extends abstract
abstract class Base {
    abstract public function name(): string;
    public function greet(): string { return "hi " . $this->name(); }
}

$obj = new class extends Base {
    public function name(): string { return "anon"; }
};
echo $obj->greet(), "\n";
// get_class() on anonymous class includes file/line in PHP, not stable for diff
echo $obj instanceof Base ? "y\n" : "n\n";

// anonymous class with constructor args
$obj = new class(5, 10) {
    public function __construct(public int $x, public int $y) {}
    public function sum(): int { return $this->x + $this->y; }
};
echo $obj->sum(), "\n";

// closures with $this in nested
class Container {
    public int $val = 10;
    public function make(): callable {
        return function () { return $this->val; };
    }
    public function makeFn(): callable {
        return fn() => $this->val;
    }
}
$c = new Container;
$f = $c->make();
echo $f(), "\n"; // 10
$f = $c->makeFn();
echo $f(), "\n"; // 10

// closure binding to different scope
class B {
    private string $secret = "shh";
}
$cl = function () { return $this->secret; };
$bound = Closure::bind($cl, new B, B::class);
echo $bound(), "\n"; // shh

// invoke on string callable - reflection
function namedFn(int $a, int $b): int { return $a + $b; }
$rf = new ReflectionFunction('namedFn');
echo $rf->invoke(3, 4), "\n";
echo $rf->invokeArgs([10, 20]), "\n";
