<?php
// a string offset fetched for a reference (a by-reference argument, a
// by-reference foreach) is php's "Cannot create references to/from string
// offsets"; one fetched as a container on the way there is "Cannot use
// string offset as an array"

set_error_handler(function ($errno, $message) {
    echo "warning: $message\n";
    return true;
});

function attempt(string $label, Closure $f) {
    try {
        $f();
        echo "$label: no error\n";
    } catch (Error $e) {
        echo "$label: ", get_class($e), ': ', $e->getMessage(), "\n";
    }
}

function byRef(&$x) { $x = 'changed'; }

attempt('argument', function () { $s = 'abc'; byRef($s[0]); });
attempt('dynamic argument', function () { $s = 'abc'; $f = 'byRef'; $f($s[1]); });
attempt('closure argument', function () { $s = 'abc'; $f = function (&$x) {}; $f($s[0]); });
attempt('element argument', function () { $a = ['k' => 'abc']; byRef($a['k'][0]); });
attempt('nested argument', function () { $s = 'abc'; byRef($s[0][1]); });
attempt('illegal offset argument', function () { $s = 'abc'; byRef($s['1x']); });
attempt('foreach', function () { $s = 'abc'; foreach ($s[0] as &$v) {} });
attempt('foreach illegal offset', function () { $s = 'abc'; foreach ($s['2bbb'] as &$v) {} });
attempt('foreach element', function () { $a = ['k' => 'abc']; foreach ($a['k'][1] as &$v) {} });
attempt('foreach nested', function () { $s = 'abc'; foreach ($s[0][0] as &$v) {} });
attempt('reference', function () { $s = 'abc'; $r = &$s[0]; });

// arrays and by-value uses are unaffected
attempt('array argument', function () { $a = ['x' => 'y']; byRef($a['x']); var_dump($a); });
attempt('vivified argument', function () { $a = []; byRef($a['p']['q']); var_dump($a); });
attempt('by value', function () { $s = 'abc'; var_dump(strlen($s[0])); });
attempt('foreach array', function () { $a = ['k' => [1, 2]]; foreach ($a['k'] as &$v) { $v *= 10; } unset($v); var_dump($a); });
