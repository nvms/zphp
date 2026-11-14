<?php
// a #[\NoDiscard] or #[\Deprecated] message that isn't a plain string is
// built with the attribute when the call warns, its constructor checking
// the argument; a TypeError from that names the attribute, not the callee
ini_set("zend.exception_ignore_args", "0");
const REASON = "computed";

#[\NoDiscard(REASON)]
function a(): int { return 1; }

#[\NoDiscard(1234)]
function b(): int { return 2; }

#[\NoDiscard(message: REASON . "!")]
function c(): int { return 3; }

#[\Deprecated(5678)]
function d() {}

#[\NoDiscard([1])]
function e(): int { return 4; }

a();
b();
c();
d();
try {
    e();
} catch (TypeError $t) {
    echo $t->getMessage(), "\n";
    echo $t->getTraceAsString(), "\n";
}
ini_set('fatal_error_backtraces', '0');
eval('class H { public $p { #[\NoDiscard] get => 1; } }');
