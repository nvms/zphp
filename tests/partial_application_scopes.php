<?php
class P {
    public static function who($x) { return static::class . " $x"; }
    public function inst($x) { return get_class($this) . " $x"; }
    public static function viaStatic() { return static::who(?); }
    public static function viaSelf() { return self::who(?); }
    public function viaParentInst() { return $this->inst(?); }
    protected function prot($x) { return "prot $x"; }
    public function getProt() { return $this->prot(?); }
    public function selfInst() { return self::inst(?); }
}
class Q extends P {
    public static function viaParent() { return parent::who(?); }
}
var_dump(Q::viaStatic()(1), Q::viaSelf()(2), Q::viaParent()(3), P::viaStatic()(4));
$q = new Q;
var_dump($q->viaParentInst()(5), $q->getProt()(6), $q->selfInst()(7));
try { $q->prot(?); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
$f = Q::who(...);
$g = $f(?);
var_dump($g(8));
var_dump((new ReflectionFunction($g))->getClosureScopeClass()?->name);
// closures with bound this
class R { public $v = 'r'; function mk() { return function ($a, $b) { return $this->v . $a . $b; }; } }
$c = (new R)->mk();
$d = $c(?, 'B');
var_dump($d('A'));
var_dump((new ReflectionFunction($d))->getClosureThis() instanceof R);
// static closure PFA
$s = static function (int ...$n) { return array_sum($n); };
$t = $s(1, 2, ...);
var_dump($t(3, 4));
echo new ReflectionFunction($t);
// generator target
function gen($a, $b) { yield $a; yield $b; }
$gg = gen(1, ?);
foreach ($gg(2) as $v) echo $v, "\n";
// return by reference
function &refret(array &$arr, $k) { return $arr[$k]; }
$data = ['a' => 1];
$rr = refret($data, ?);
$x = &$rr('a');
$x = 99;
var_dump($data);
// nested named + variadic extras
function ex($a, ...$rest) { return [$a, $rest]; }
$e1 = ex(?, z: 1, ...);
var_dump($e1(0, 5, y: 2));
// placeholders binding to variadic
$e2 = ex(?, ?, ?);
echo new ReflectionFunction($e2);
var_dump($e2(1, 2, 3));
// default from constant
const DEF = 'def';
function cd($a, $b = DEF, $c = [1, 'x' => [2]]) { return [$a, $b, $c]; }
$cdp = cd(?, ...);
echo new ReflectionFunction($cdp);
var_dump($cdp(1));
// array_map / usort integration
var_dump(array_map(str_repeat(?, 2), ['a', 'b']));
$arr = [3, 1, 2];
usort($arr, strcmp(...));
var_dump($arr);
