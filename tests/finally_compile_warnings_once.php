<?php
// php compiles a finally block once: a warning from code in it (a closure's
// own finally return, a deprecated type name) is raised once, however many
// ways out of the try there are
set_error_handler(function ($no, $msg, $file, $line) { echo "$no: $msg (line $line)\n"; return true; });
eval('function f($x) {
    try {
        if ($x) return 1;
        foreach ([1] as $v) { if ($v) break; }
    } finally {
        $g = function () {
            try {
                return 1;
            } finally {
                return 2;
            }
        };
        $h = function (_ $a) {};
    }
    return 0;
}');
var_dump(f(true), f(false));
