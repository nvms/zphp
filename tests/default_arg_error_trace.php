<?php
// an error raised by a parameter's default is raised in the callee's frame
function foo($a = UNKNOWN_X) {
}
function bar($x, $a = [1 => UNKNOWN_Y]) {
}
try { foo(); } catch (Error $e) { echo $e->getMessage(), "\n", $e->getTraceAsString(), "\n", $e->getLine(), "\n"; }
try { bar(1); } catch (Error $e) { echo $e->getMessage(), "\n", $e->getTraceAsString(), "\n", $e->getLine(), "\n"; }
class C { function m($a = UNKNOWN_W) {} static function s($a = UNKNOWN_Z) {} }
try { (new C)->m(); } catch (Error $e) { echo $e->getMessage(), "\n", $e->getTraceAsString(), "\n"; }
try { C::s(); } catch (Error $e) { echo $e->getMessage(), "\n", $e->getTraceAsString(), "\n"; }
