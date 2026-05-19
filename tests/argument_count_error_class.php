<?php
// regression: ArgumentCountError is a registered subclass of TypeError
// (extends TypeError -> Error -> Throwable). previously zphp threw with
// the class name 'ArgumentCountError' but the class wasn't in vm.classes,
// so methods like getMessage() raised 'undefined method'. also expand the
// 'Too few arguments' message to PHP's full format with the caller
// location and 'exactly|at least N expected' tail

function fixed($a, $b, $c) { return "$a $b $c"; }
function optional($a, $b = 2, $c = 3) { return "$a $b $c"; }

try { fixed(1); }
catch (\ArgumentCountError $e) {
    echo "fix: " . $e->getMessage() . "\n";
    echo "is TypeError: " . ($e instanceof \TypeError ? 'y' : 'n') . "\n";
    echo "is Error: " . ($e instanceof \Error ? 'y' : 'n') . "\n";
    echo "is Throwable: " . ($e instanceof \Throwable ? 'y' : 'n') . "\n";
}

try { optional(); }
catch (\ArgumentCountError $e) { echo "opt: " . $e->getMessage() . "\n"; }

// 'at least N expected' modifier when there are optional params
function some_optional($a, $b, $c = 3, $d = 4) { return "$a$b$c$d"; }
try { some_optional(1); }
catch (\ArgumentCountError $e) { echo "min: " . $e->getMessage() . "\n"; }
