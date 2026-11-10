<?php
// extract, compact and array_key_exists as php's array.c does them
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
function t(callable $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
var_dump(EXTR_PREFIX_IF_EXISTS, EXTR_IF_EXISTS);

function scope() {
    $a = "orig";
    $unset_cv = null;
    unset($unset_cv);
    $data = ["a" => 1, "b" => 2, "1x" => 3, 5 => "five", "" => "empty", "unset_cv" => "set", "ü" => "utf"];
    var_dump(extract($data, EXTR_SKIP), $a, $b);
    var_dump(extract($data, EXTR_PREFIX_SAME, "p"), $p_a);
    var_dump(extract($data, EXTR_PREFIX_ALL, "q"), $q_5, $q_1x);
    var_dump(extract($data, EXTR_PREFIX_INVALID, "r"), $r_5, $r_1x);
    var_dump(extract($data, EXTR_IF_EXISTS));
    var_dump(extract($data, EXTR_PREFIX_IF_EXISTS, "s"), $s_a);
    var_dump(extract([1, 2, 3]));
    var_dump(extract(["x" => 1], EXTR_PREFIX_ALL, ""), $_x);
    var_dump(extract(["GLOBALS" => 1]));
    t(fn() => extract([], -1));
    t(fn() => extract([], 99));
    t(fn() => extract([], EXTR_PREFIX_SAME));
    t(fn() => extract([], EXTR_PREFIX_ALL, "1bad"));
    t(fn() => extract(["this" => 1]));
    var_dump(compact("a", ["b", ["q_5"]], "nope", 5, true));
    var_dump(compact("this"));
}
scope();

class K { function m() { return compact("this"); } }
var_dump(count((new K)->m()));

$arr = ["" => 1, 1 => 2, 0 => 3];
t(fn() => array_key_exists(null, $arr));
t(fn() => array_key_exists(1.5, $arr));
t(fn() => array_key_exists(1.0000000000000002, $arr));
t(fn() => array_key_exists(true, $arr));
t(fn() => array_key_exists("1", $arr));
t(fn() => array_key_exists([], $arr));
t(fn() => array_key_exists(new K, $arr));
t(fn() => key_exists(0, $arr));
