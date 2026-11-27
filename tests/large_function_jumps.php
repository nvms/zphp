<?php
// generated functions whose bodies are longer than a 16-bit jump reaches:
// branches, loops, handlers and argument lists spanning more than 64 KB of
// bytecode

function statements(int $n, string $var = '$t'): string
{
    $s = '';
    for ($i = 0; $i < $n; $i++) $s .= "$var += \$w + " . ($i % 97) . "; ";
    return $s;
}

$code = [];
$huge = '[' . implode(', ', range(1, 20000)) . ']';

// a 20,000-branch elseif chain
$s = 'function classify($x) { if ($x === -1) { return "neg"; }';
for ($i = 0; $i < 20000; $i++) $s .= " elseif (\$x === $i) { return 'b$i'; }";
$s .= ' else { return "none"; } }';
$code[] = $s;

// a switch over 30,000 int cases and a match over 30,000 strings
$s = 'function sw($x) { switch ($x) {';
for ($i = 0; $i < 30000; $i++) $s .= " case $i: return 'i$i';";
$s .= ' default: return "default"; } }';
$code[] = $s;
$s = 'function mt($x) { return match ($x) {';
for ($i = 0; $i < 30000; $i++) $s .= " 'k$i' => 'mk$i',";
$s .= ' default => "nomatch" }; }';
$code[] = $s;

// loops whose bodies are longer than 64 KB, with break and continue
$code[] = 'function loops() { $out = []; $t = 0; $w = 1;'
    . ' for ($i = 0; $i < 3; $i++) { if ($i == 1) continue; ' . statements(8000) . ' $out[] = "for$i"; }'
    . ' foreach (["a" => 1, "b" => 2, "c" => 3] as $k => $v) { ' . statements(8000) . ' if ($k == "b") break; $out[] = "each$k"; }'
    . ' $n = 0; while (true) { $n++; ' . statements(8000) . ' if ($n >= 2) break; }'
    . ' do { ' . statements(8000) . ' $n--; } while ($n > 0);'
    . ' $lim = 2; for ($j = 0; $j < $lim; $j++) { ' . statements(8000) . ' $out[] = "lim$j"; }'
    . ' $list = [1, 2]; foreach ($list as $v) { ' . statements(8000) . ' $out[] = "nokey$v"; }'
    . ' foreach ($list as &$v) { ' . statements(8000) . ' $v *= 100; } unset($v); $out[] = $list;'
    . ' $out[] = $t; return $out; }';

// operators whose skipped operand is longer than 64 KB, and a static
// variable whose initializer is
$code[] = 'function operands($x) { static $table = ' . $huge . '; static $calls = 0; $calls++;'
    . ' $a = $x || count(' . $huge . ') > 0; $b = $x && count(' . $huge . ') > 0;'
    . ' $c = $x ?? count(' . $huge . '); $d = $x ?: count(' . $huge . '); $e = $x ? "yes" : count(' . $huge . ');'
    . ' return [$a, $b, $c, $d, $e, count($table), $table[19999], $calls]; }';

// try, catch and finally around more than 64 KB, rethrown from the far end
$code[] = 'function handlers($throw) { $t = 0; $w = 2; $log = [];'
    . ' try { ' . statements(8000) . ' if ($throw) throw new RuntimeException("far"); $log[] = "body"; }'
    . ' catch (LogicException $e) { $log[] = "logic"; }'
    . ' catch (RuntimeException $e) { ' . statements(8000) . ' $log[] = "caught " . $e->getMessage(); }'
    . ' finally { ' . statements(8000) . ' $log[] = "finally"; }'
    . ' try { try { ' . statements(8000) . ' throw new Exception("inner"); } finally { $log[] = "inner finally"; } } catch (Exception $e) { $log[] = $e->getMessage(); }'
    . ' $log[] = $t; return $log; }';

// arguments passed by reference with more than 64 KB of arguments between
// them and the call
$code[] = 'function byref(&$a, $big, &$b) { $a = count($big); $b = array_sum($big); }';
$code[] = 'function addAll(&...$refs) { foreach ($refs as &$r) $r *= 10; }';
$code[] = 'function refs() { $p = 0; $q = 0; byref($p, ' . $huge . ', $q);'
    . ' $arr = [3, 1, 2]; array_splice($arr, 1, 1, ' . $huge . ');'
    . ' $vals = [1, 2, 3]; addAll(...$vals, ...' . $huge . ');'
    . ' $m = []; preg_match("/(b)(c)/", "abc" . implode(",", ' . $huge . '), $m);'
    . ' $o = new stdClass(); $d = []; byref($o->p, ' . $huge . ', $d["k"]); byref($d["a"]["b"], ' . $huge . ', $o->{"q"});'
    . ' $f = "byref"; $f($o->r, ' . $huge . ', $d["z"]);'
    . ' return [$p, $q, count($arr), $arr[0], $arr[20000], $vals, $m, $o, $d]; }';

// closures, generators and method calls placed past the first 64 KB
$code[] = 'class Far { public $v = 5; function twice($x) { return $x * 2; } static function make() { return new self(); } }';
$code[] = 'function late() { $t = 0; $w = 3; ' . statements(8000)
    . ' $f = function ($x) use (&$t) { return $x + $t; };'
    . ' $g = (function () use ($t) { for ($i = 0; $i < 3; $i++) { yield $i => $t + $i; } })();'
    . ' $o = Far::make(); return [$t, $f(1), iterator_to_array($g), $o->twice($o->v), $t > 0 ? "pos" : "neg", $t ?: "zero", $o?->v ?? "none"]; }';

// a generator whose body is longer than 64 KB
$code[] = 'function bigGen() { $t = 0; $w = 4; for ($i = 0; $i < 3; $i++) { ' . statements(8000) . ' yield $i => $t; } return "done"; }';

// an assert whose expression is longer than 64 KB
$groups = [];
for ($g = 0; $g < 40; $g++) $groups[] = '(' . implode(' + ', array_fill(0, 1000, '$x')) . ')';
$code[] = 'function asserted($x) { assert(' . implode(' + ', $groups) . ' > 0, "positive"); return "after assert"; }';

// a long nullsafe chain
$code[] = 'function chain($o) { return $o' . str_repeat('?->next', 9000) . '?->v; }';

// each compiled on its own, as separate files would be
foreach ($code as $c) eval($c);
unset($code, $c);

foreach ([-1, 0, 1, 19999, 20000, 'x'] as $x) echo classify($x), ' ';
echo "\n";
foreach ([0, 29999, 'k0', 'k29999', 30000, '5'] as $x) echo sw($x), ' ', mt($x), ' ';
echo "\n";
var_dump(loops());
var_dump(operands(0), operands(null), operands(7));
var_dump(handlers(true));
var_dump(handlers(false));
var_dump(refs());
var_dump(late());
$gen = bigGen();
foreach ($gen as $k => $v) echo "$k=$v ";
echo $gen->getReturn(), "\n";
var_dump(asserted(1));
$o = null;
for ($i = 0; $i < 9001; $i++) {
    $n = new stdClass();
    $n->next = $o;
    $n->v = "v$i";
    $o = $n;
}
var_dump(chain($o), chain(null));
$o->next->next = null;
var_dump(chain($o));
