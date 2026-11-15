<?php
// dimension fetches on containers that aren't arrays, and offsets php
// converts with a diagnostic, as zend_fetch_dimension_address does
function t($label, $f) {
    echo "$label: ";
    try { $f(); echo "ok\n"; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
}
foreach (['res' => STDERR, 'obj' => new stdClass, 'int' => 4, 'true' => true, 'float' => 5.5] as $n => $c0) {
    echo "== $n\n";
    t("w", function () use ($c0) { $c = $c0; $c[1] = 5; });
    t("w2", function () use ($c0) { $c = $c0; $c[1][2] = 5; });
    t("w3", function () use ($c0) { $c = $c0; $c[1][2][3] = 5; });
    t("app", function () use ($c0) { $c = $c0; $c[] = 5; });
    t("rw", function () use ($c0) { $c = $c0; $c[1] += 5; });
    t("inc", function () use ($c0) { $c = $c0; $c[1]++; });
    t("r", function () use ($c0) { $c = $c0; var_dump($c[1]); });
    t("r2", function () use ($c0) { $c = $c0; var_dump($c[1][2]); });
    t("isset", function () use ($c0) { $c = $c0; var_dump(isset($c[1])); });
    t("isset2", function () use ($c0) { $c = $c0; var_dump(isset($c[1][2])); });
    t("empty", function () use ($c0) { $c = $c0; var_dump(empty($c[1])); });
    t("coal", function () use ($c0) { $c = $c0; var_dump($c[1] ?? 'd'); });
    t("coal2", function () use ($c0) { $c = $c0; var_dump($c[1][2] ?? 'd'); });
    t("ref", function () use ($c0) { $c = $c0; $r = &$c[1]; });
    t("ref2", function () use ($c0) { $c = $c0; $r = &$c[1][2]; });
    t("refapp", function () use ($c0) { $c = $c0; $r = &$c[]; });
    t("bind", function () use ($c0) { $c = $c0; $x = 1; $c[1] = &$x; });
    t("bindapp", function () use ($c0) { $c = $c0; $x = 1; $c[] = &$x; });
    t("unset", function () use ($c0) { $c = $c0; unset($c[1]); });
    t("unset2", function () use ($c0) { $c = $c0; unset($c[1][2]); });
    t("coalasg", function () use ($c0) { $c = $c0; $c[1] ??= 3; });
    t("list", function () use ($c0) { $c = $c0; [$c[1]] = [3]; });
    t("foreach", function () use ($c0) { $c = $c0; foreach ([1] as $c[1]); });
    $GLOBALS['g'] = $c0;
    t("gw", function () { global $g; $g[1] = 5; });
    t("gw2", function () { global $g; $g[1][2] = 5; });
    t("gr", function () { global $g; var_dump($g[1]); });
    t("gisset", function () { global $g; var_dump(isset($g[1])); });
    t("gref", function () { global $g; $r = &$g[1]; });
    t("prop", function () use ($c0) { $o = new stdClass; $o->p = $c0; $o->p[1] = 5; });
    t("propr", function () use ($c0) { $o = new stdClass; $o->p = $c0; var_dump($o->p[1]); });
    t("propisset", function () use ($c0) { $o = new stdClass; $o->p = $c0; var_dump(isset($o->p[1])); });
    t("elem", function () use ($c0) { $a = [1 => $c0]; $a[1][2] = 5; });
    t("elemr", function () use ($c0) { $a = [1 => $c0]; var_dump($a[1][2]); });
    t("elemisset", function () use ($c0) { $a = [1 => $c0]; var_dump(isset($a[1][2])); });
    t("elemunset", function () use ($c0) { $a = [1 => $c0]; unset($a[1][2]); });
    // the global scope reaches its variables by name
    $c = $c0;
    try { $c[1] = 5; echo "ok\n"; } catch (Error $e) { echo $e->getMessage(), "\n"; }
    try { $c["k"][2] = 5; echo "ok\n"; } catch (Error $e) { echo $e->getMessage(), "\n"; }
}

echo "== keys\n";
$d = 5.5; $c = []; $c[$d][$d] = 5; var_dump($c);
$d = NAN; $c = []; $c[$d] = 1; var_dump($c);
$d = "7"; $c = []; var_dump($c[$d][$d]);
$c = null; try { $c[[]] = 5; } catch (Error $e) { echo $e->getMessage(), "\n"; } var_dump($c);
$c = null; try { $r = &$c[[]]; } catch (Error $e) { echo $e->getMessage(), "\n"; } var_dump($c);
$c = []; try { $c[new stdClass][1] = 5; } catch (Error $e) { echo $e->getMessage(), "\n"; } var_dump($c);
$c = []; try { $c[1][new stdClass] = 5; } catch (Error $e) { echo $e->getMessage(), "\n"; } var_dump($c);
$c = []; $r = &$c[null]; $r = 1; $s = &$c[]; $s = 2; var_dump($c);
unset($r, $s);

echo "== strings\n";
foreach ([null, true, 1.5, "1x", "x", [], 1] as $k) {
    $s = "abc";
    try { $s[$k] .= "z"; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
    try { $s[$k][0] = "z"; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
    try { $r = &$s[$k]; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
    try { $s[$k]++; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
    try { $s[$k]->p = 1; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
    try { var_dump(isset($s[$k]), empty($s[$k])); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
}
var_dump(isset($s[2.5]), empty($s["1x"]), isset($s[1e20]), empty($s[NAN]));

echo "== references into objects\n";
class A implements ArrayAccess {
    function offsetGet($o): mixed { echo "get\n"; return 1; }
    function offsetSet($o, $v): void {}
    function offsetExists($o): bool { return true; }
    function offsetUnset($o): void {}
}
$x = 1;
foreach ([new A, "abc", 5, new stdClass] as $c) {
    try { $c[1] = &$x; } catch (Error $e) { echo $e->getMessage(), "\n"; }
    try { $c[] = &$x; } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
