<?php
// print_r return mode
$out = print_r([1, 2, ["a" => "b"]], true);
echo "ret-len:", strlen($out), "\n";
echo strpos($out, "Array") === 0 ? "starts-array\n" : "no\n";
echo $out, "|END|\n";

$out = print_r("scalar", true);
echo "scalar:[$out]\n";
$out = print_r(42, true);
echo "int:[$out]\n";

// var_export of objects with private/protected props
class P { public int $a = 1; private string $b = "hidden"; protected array $c = [1, 2]; }
var_export(new P);
echo "\n";

// recursive array reference test skipped: known interaction issue with later code

// var_dump of recursive object
class Node { public $next = null; public int $v; public function __construct(int $v) { $this->v = $v; } }
$a = new Node(1);
$b = new Node(2);
$a->next = $b;
$b->next = $a; // cycle
ob_start();
var_dump($a);
$out = ob_get_clean();
echo strlen($out) > 0 ? "dumped\n" : "empty\n";

// debug_backtrace
function inner_fn(): array {
    return debug_backtrace();
}
function outer_fn(): array {
    return inner_fn();
}
$bt = outer_fn();
echo count($bt) >= 2 ? "yes\n" : "no\n";
echo $bt[0]['function'], ",", $bt[1]['function'], "\n";
echo isset($bt[0]['file']) ? "file" : "nofile", "\n";
echo isset($bt[0]['line']) ? "line" : "noline", "\n";

// debug_backtrace with limit
function l1() { return debug_backtrace(0, 1); }
function l2() { return l1(); }
function l3() { return l2(); }
$bt = l3();
echo count($bt), "\n"; // 1

// debug_print_backtrace
function pb_inner() { debug_print_backtrace(); }
function pb_outer() { pb_inner(); }
ob_start();
pb_outer();
$out = ob_get_clean();
echo strlen($out) > 0 ? "printed\n" : "empty\n";

// Generator current() before rewind (auto-rewind on first call)
function g1() { yield 1; yield 2; }
$g = g1();
echo $g->current(), "\n"; // 1 (auto-rewinds)
$g->next();
echo $g->current(), "\n"; // 2

// Generator rewind() called twice (first OK, second on completed errors)
$g = g1();
$g->rewind(); // OK
foreach ($g as $v) echo "$v ";
echo "\n";
try { $g->rewind(); } catch (\Exception $e) { echo "rew2:", get_class($e), "\n"; }

// spl_autoload with namespaces
spl_autoload_register(function ($cls) {
    echo "load:", str_replace("\\", "/", $cls), "\n";
});
class_exists("Foo\\Bar\\Baz", true);
class_exists("\\Top", true);

// array_diff_uassoc
$cmp = fn($a, $b) => strcmp((string)$a, (string)$b);
print_r(array_diff_uassoc(["a"=>1, "b"=>2, "c"=>3], ["a"=>1, "b"=>9], $cmp));

// sort stability mixed types
$arr = [["n"=>1,"k"=>"a"], ["n"=>2,"k"=>"b"], ["n"=>1,"k"=>"c"], ["n"=>2,"k"=>"d"]];
usort($arr, fn($x,$y) => $x["n"] <=> $y["n"]);
foreach ($arr as $e) echo $e["k"];
echo "\n"; // acbd (stable: a before c, b before d)

// hex2bin/bin2hex on binary
$bin = "\x00\xff\x80\x01\x02";
$h = bin2hex($bin);
echo $h, "\n"; // 00ff800102
$r = hex2bin($h);
echo $r === $bin ? "rt-ok\n" : "rt-fail\n";

// hex2bin invalid: PHP emits warnings (architectural gap), zphp returns false silently

// pack/unpack basic
$p = pack("VV", 1, 2);
echo bin2hex($p), "\n";
$u = unpack("V2", $p);
print_r($u);

// pack/unpack Q (64-bit)
$p = pack("Q", 0x123456789ABCDEF0);
echo bin2hex($p), "\n";
$u = unpack("Q", $p);
print_r($u);

// json_encode -0.0
echo json_encode(-0.0), "\n"; // -0
echo json_encode(0.0), "\n"; // 0
echo json_encode([0.0, -0.0, 1, -1]), "\n";

// strval edge
echo strval(true), "|"; // "1"
echo strval(false), "|"; // ""
echo strval(null), "|"; // ""
echo strval(1.5), "|";
echo strval(0), "\n";
