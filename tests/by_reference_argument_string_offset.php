<?php
// a string offset can't be passed by reference: the write fetch refuses it,
// naming what the next link of the chain would have done with it
function byRef(&$a) {}
eval('function lateByRef(&$a) {}');

$cases = [
    'offset' => function () { $s = "abc"; byRef($s[0]); },
    'offset late' => function () { $s = "abc"; lateByRef($s[1]); },
    'nested' => function () { $s = "abc"; byRef($s[0][0]); },
    'in array' => function () { $a = ['k' => "abc"]; byRef($a['k'][0]); },
    'in property' => function () { $o = new stdClass; $o->p = "abc"; lateByRef($o->p[0]); },
    'string key' => function () { $s = "abc"; byRef($s["1"]); },
    'bad key' => function () { $s = "abc"; byRef($s["x"]); },
];
foreach ($cases as $label => $case) {
    try {
        $case();
        echo "$label: passed\n";
    } catch (Throwable $e) {
        echo "$label: ", $e::class, ': ', $e->getMessage(), "\n";
    }
}

// a by-value parameter reads the offset
function byValue($a) { return $a; }
$s = "xyz";
var_dump(byValue($s[2]));
