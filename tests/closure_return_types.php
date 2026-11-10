<?php
// a closure's declared return type is checked and coerced like a function's

$int = function ($v): int { return $v; };
$float = fn ($v): float => $v;
$string = static function ($v): string { return $v; };

var_dump($int("1"), $int(2.0), $float(3), $string(4));
foreach ([[$int, "x"], [$float, []], [$string, null]] as [$f, $v]) {
    try {
        var_dump($f($v));
    } catch (TypeError $e) {
        echo preg_replace('/\{closure:[^}]*\}/', '{closure}', $e->getMessage()), "\n";
    }
}
