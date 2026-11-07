<?php
// php has no limit on how many arguments a call passes: written out in the
// call, unpacked from arrays, or both, to any kind of callee

function f(...$a) { return count($a) . ':' . array_sum($a); }
function g($x, $y = 2, ...$rest) { return func_num_args() . '/' . count(func_get_args()) . '/' . count($rest) . '/' . array_sum(func_get_args()); }
function h() { return func_num_args() . '/' . array_sum(func_get_args()); }
function r(&$ref, ...$rest) { $ref = count($rest); }
function named($a, $b, ...$rest) { return "$a $b " . count($rest) . ' ' . implode(',', array_keys(array_filter($rest, 'is_string', ARRAY_FILTER_USE_KEY))); }
function thrower(...$a) { throw new Exception('x'); }

class C {
    function m(...$a) { return count($a); }
    static function s(...$a) { return static::class . count($a); }
    function __construct(...$a) { echo "ctor ", count($a), "\n"; }
    function __call($n, $a) { return "__call $n " . count($a); }
    static function __callStatic($n, $a) { return "__callStatic $n " . count($a); }
}
class D extends C {
    static function t() {
        $r = range(1, 300);
        return parent::s(...$r) . ' ' . self::s(...$r) . ' ' . static::s(...$r);
    }
}

// 300 arguments written out
$lit = implode(', ', range(0, 299));
eval(<<<PHP
\$o = new C($lit);
echo f($lit), "\\n";
echo g($lit), "\\n";
echo h($lit), "\\n";
echo \$o->m($lit), "\\n";
\$mn = 'm';
echo \$o->\$mn($lit), "\\n";
echo \$o?->m($lit), "\\n";
echo C::s($lit), "\\n";
\$c = 'C';
echo \$c::s($lit), "\\n";
\$sn = 's';
echo \$c::{\$sn}($lit), "\\n";
echo \$c::\$sn($lit), "\\n";
\$fn = 'f';
echo \$fn($lit), "\\n";
\$cl = function (...\$a) { return count(\$a); };
echo \$cl($lit), "\\n";
echo call_user_func('f', $lit), "\\n";
echo max($lit), ' ', min($lit), "\\n";
echo strlen(sprintf(str_repeat('%d', 300), $lit)), "\\n";
r(\$v, $lit);
echo \$v, "\\n";
\$x = new class($lit) { function __construct(...\$a) { echo 'anon ', count(\$a), "\\n"; } };
PHP);

// more unpacked arguments than a frame's operand stack headroom
$big = range(1, 300);
$huge = range(1, 20000);
$o = new C(...$huge);
echo f(...$big), "\n";
echo f(...$huge, ...$huge), "\n";
echo g(...$big), "\n";
echo g(...$huge), "\n";
echo h(...$huge), "\n";
echo $o->m(...$huge), "\n";
echo $o->nope(...$huge), "\n";
echo $o->$mn(...$huge), "\n";
echo $o?->m(...$huge), "\n";
echo C::s(...$huge), "\n";
echo C::nope(...$huge), "\n";
echo $c::s(...$huge), "\n";
echo (new C)::s(...$big), "\n";
echo C::{$sn}(...$big), "\n";
echo D::t(), "\n";
echo $fn(...$huge), "\n";
echo $cl(...$huge), "\n";
$ar = fn(...$a) => count($a);
echo $ar(...$huge), "\n";
echo call_user_func_array('f', $huge), "\n";
echo call_user_func_array([$o, 'm'], $huge), "\n";
echo call_user_func_array('C::s', $huge), "\n";
echo call_user_func_array($cl, $huge), "\n";
echo max(...$huge), ' ', min(...$huge), "\n";
echo count(array_merge(...array_fill(0, 1000, [1, 2]))), "\n";
echo strlen(sprintf(str_repeat('%d', 20000), ...$huge)), "\n";
echo count(array_map(null, ...array_fill(0, 300, [1]))[0]), "\n";
r($w, ...$huge);
echo $w, "\n";
$a = [1, 2, 3];
r($u, ...$a);
echo $u, "\n";
echo f(...$big, x: 5), "\n";
echo named(...$big, z: 1), "\n";
echo named(...$huge, z: 1), "\n";
try {
    thrower(...$big);
} catch (Exception $e) {
    echo count($e->getTrace()[0]['args']), "\n";
}
echo (new ReflectionFunction('f'))->invokeArgs($huge), "\n";
echo (new ReflectionMethod('C', 'm'))->invokeArgs($o, $huge), "\n";
echo (new ReflectionClass('C'))->newInstanceArgs($big) instanceof C ? "ok\n" : "no\n";
$x = new class(...$big) { function __construct(...$a) { echo 'anon ', count($a), "\n"; } };

// unpacked arguments reach by-reference parameters, beside written ones
function two(&$a, &$b) { $a = 'A'; $b = 'B'; }
class K {
    function m(&$a, $b) { $a = "m$b"; }
    static function s(&$a) { $a = 's'; }
}
$p = 0; $q = 0;
two($p, ...[&$q]);
var_dump($p, $q);
$km = 0;
(new K)->m(...[&$km, 5]);
var_dump($km);
$ks = 0;
K::s(...[&$ks]);
var_dump($ks);
