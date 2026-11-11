<?php
// one call site calling closures that take the same argument by value and
// by reference: each call binds as its own closure declares

function run($f, $label) {
    $x = 1;
    $f($x);
    echo $label, ": ", $x, "\n";
}

$byValue = function ($v) { $v = 10; };
$byRef = function (&$v) { $v = 20; };
for ($i = 0; $i < 3; $i++) {
    run($byValue, "value");
    run($byRef, "reference");
}

$closures = [];
for ($i = 0; $i < 4; $i++) {
    $closures[] = $i % 2 ? function (&$v) { $v = 30; } : function ($v) { $v = 40; };
}
foreach ($closures as $k => $f) {
    run($f, "made $k");
}

// a closure's __invoke and a method named __invoke
class Invokable {
    public function __invoke(&$v) { $v = 6; }
}
$y = 1;
(new Invokable)->__invoke($y);
echo $y, "\n";
$c = function (&$v) { $v = 7; };
$y = 1;
$c->__invoke($y);
echo $y, "\n";
