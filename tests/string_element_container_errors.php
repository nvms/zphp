<?php
// using a string or scalar array element as a container must produce PHP's
// errors instead of silently clobbering the element with a fresh array

function t($label, $fn) {
    try {
        $r = $fn();
        echo $label, ": ", var_export($r, true), "\n";
    } catch (Error $e) {
        echo $label, ": ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}

t("str-elem-append", function () { $a = [0 => "x"]; $a[0][] = 3; return $a[0]; });
t("str-elem-deep", function () { $a = [0 => "x"]; $a[0][1][] = 3; return $a[0]; });
t("str-elem-strkey", function () { $a = [0 => "x"]; $a[0]["k"] = 3; return $a[0]; });
t("str-elem-charwrite", function () { $a = [0 => "xy"]; $a[0][1] = "z"; return $a[0]; });
t("str-elem-charpad", function () { $a = [0 => "x"]; $a[0][5] = 3; return $a[0]; });
t("str-elem-numstrkey", function () { $a = [0 => "xy"]; $a[0]["1"] = "z"; return $a[0]; });
t("str-local-append", function () { $s = "x"; $s[] = 3; return $s; });
t("str-prop-append", function () { $o = new stdClass; $o->p = "x"; $o->p[] = 3; return $o->p; });
t("str-prop-strkey", function () { $o = new stdClass; $o->p = "x"; $o->p["k"] = 3; return $o->p; });
t("str-prop-elem-append", function () { $o = new stdClass; $o->p = [0 => "x"]; $o->p[0][] = 3; return $o->p[0]; });
t("int-elem-append", function () { $a = [0 => 5]; $a[0][] = 3; return $a[0]; });
t("int-elem-deep", function () { $a = [0 => 5]; $a[0][1][2] = 3; return $a[0]; });
t("float-elem-append", function () { $a = [0 => 1.5]; $a[0][] = 3; return $a[0]; });
t("true-elem-append", function () { $a = [0 => true]; $a[0][] = 3; return $a[0]; });
t("null-elem-append", function () { $a = [0 => null]; $a[0][] = 3; return $a[0]; });

class S { public static $p = "x"; }
t("str-static-append", function () { S::$p[] = 3; return S::$p; });
