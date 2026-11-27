<?php
// generated code whose functions hold more literals than a 16-bit constant
// index reaches: big literal arrays, long constant expressions, and calls,
// closures and generators compiled after the pool has grown past 65536

function literals(int $n, string $kind): string
{
    $parts = [];
    for ($i = 0; $i < $n; $i++) {
        $parts[] = match ($kind) {
            'string' => "'s$i' => 'v$i'",
            'float' => "$i.25",
            'int' => (string)($i * 7 + 1000000),
        };
    }
    return '[' . implode(', ', $parts) . ']';
}

class Probe
{
    public $log = [];
    function hello($x) { return "hello $x"; }
    function bye($x) { return "bye $x"; }
    static function make() { return new static(); }
}

$code = [];
$code[] = 'function big_strings() { $a = ' . literals(70000, 'string') . '; $p = new Probe(); return [count($a), $a["s0"], $a["s69999"], $p->hello(1), $p->bye(2), Probe::make()::class]; }';
$code[] = 'function big_floats() { $a = ' . literals(70000, 'float') . '; $f = fn($x) => $x * 2; return [count($a), $a[0], $a[69999], array_sum($a), $f(21)]; }';
$code[] = 'function big_ints() { $a = ' . literals(70000, 'int') . '; $g = (function () { yield 1; yield 2; yield "three"; })(); return [count($a), $a[0], $a[69999], array_sum($a), iterator_to_array($g)]; }';
// one expression with more distinct terms than u16 indexes
// (in groups: php's compiler recurses once per operator)
$groups = [];
for ($g = 0; $g < 140; $g++) {
    $terms = [];
    for ($i = 0; $i < 500; $i++) $terms[] = (string)($g * 500 + $i + 100000);
    $groups[] = '(' . implode(' + ', $terms) . ')';
}
$code[] = 'function big_sum($x) { return $x + ' . implode(' + ', $groups) . '; }';
// and as constant expressions: a constant, a class constant, a default
$code[] = 'const BIG_TOTAL = ' . implode(' + ', $groups) . ';';
$code[] = 'class BigConst { const TOTAL = ' . implode(' + ', $groups) . '; }';
$code[] = 'function big_default($x = ' . implode(' + ', $groups) . ') { return $x; }';
$groups = [];
for ($g = 0; $g < 140; $g++) {
    $words = [];
    for ($i = 0; $i < 500; $i++) $words[] = "\$x[" . ($i % 3) . "] . 'w" . ($g * 500 + $i) . "'";
    $groups[] = '(' . implode(' . ', $words) . ')';
}
$code[] = 'function big_concat($x) { $s = ""; $s .= ' . implode('; $s .= ', $groups) . '; return [strlen($s), md5($s), str_contains($s, "w69999")]; }';

// each compiled on its own, as separate files would be
foreach ($code as $c) eval($c);
unset($code, $c);
var_dump(big_strings());
var_dump(big_floats());
var_dump(big_ints());
var_dump(big_sum(1));
var_dump(BIG_TOTAL, BigConst::TOTAL, big_default(), big_default(3));
var_dump(big_concat(['a', 'b', 'c']));

// the same shapes at the top level of an included file, with a class
// declared and used after the literals
$file = tempnam(sys_get_temp_dir(), 'zphp_pool');
$top = "<?php\n\$big = " . literals(40000, 'string') . ";\n";
$top .= "\$nums = " . literals(30000, 'float') . ";\n";
$top .= "class After { const C = 'after'; public \$p = 'prop'; function m(\$v) { return [self::C, \$this->p, \$v]; } }\n";
$top .= "\$o = new After();\n";
$top .= "\$cl = function (\$v) use (\$big) { return \$big['s' . \$v]; };\n";
$top .= "function gen_after() { yield 'x' => 1; yield 'y' => 2; }\n";
$top .= "return [count(\$big), \$big['s39999'], count(\$nums), \$nums[29999], \$o->m(5), \$cl(12345), iterator_to_array(gen_after()), strtoupper('done'), PHP_INT_SIZE, M_PI > 3];\n";
file_put_contents($file, $top);
var_dump(include $file);
unlink($file);
