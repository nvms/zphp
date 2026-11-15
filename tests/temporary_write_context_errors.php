<?php
// writes php refuses at run time: a fetch from a temporary passed by
// reference, $this through a variable variable, an unset into a string

const C = ['c'];
function attempt(callable $f): void {
    try {
        $f();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$byRef = function (&$ref) { echo "bound\n"; };
$byVal = function ($v) { var_dump($v); };
function args() {
    global $byRef, $byVal;
    $byVal(func_get_args()[0]);
    attempt(function () use ($byRef) { $byRef(func_get_args()[0]); });
}
args('x');
attempt(fn() => $byRef([0, 1][0]));
attempt(fn() => $byRef([0, 1]->prop));
attempt(fn() => $byRef(C[0]));
attempt(fn() => $byRef(C[0][0]));
$byVal([0, 1][1]);
$byVal(C[0]);
$v = [[1]];
$byRef($v[0][0]);

function reassign() {
    $a = "this";
    $$a = 0;
}
attempt('reassign');
attempt(function () {
    $name = "this";
    $$name = 1;
});

$s = "test";
attempt(function () use ($s) { unset($s["a"]["b"]["c"]); });
attempt(function () use ($s) { unset($s["a"]["b"]); });
attempt(function () use ($s) { unset($s[0]); });
attempt(function () { $a = ["x" => "str"]; unset($a["x"]["y"]["z"]); });
// the offset decides which refusal: one that is an integer can't be
// descended into, any other can't be unset
foreach ([0, "0", "1abc", " 2", "a", "1.5", "1e3", null, true, "99999999999999999999"] as $k) {
    $x = "str";
    try {
        unset($x[$k][0]);
    } catch (Error $e) {
        echo json_encode($k), ": ", $e->getMessage(), "\n";
    }
}
echo "done\n";
