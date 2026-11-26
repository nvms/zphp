<?php
// errors a parameter default raises belong to the function's own frame
function b($a = array()[array ()]) {}
try { b(); } catch (Error $e) { echo $e->getMessage(), "\n", $e->getTraceAsString(), "\n"; }

class C { function m($x, $a = array()[array ()]) {} }
try { (new C)->m(1); } catch (Error $e) { echo $e->getTraceAsString(), "\n"; }

class E { function __construct($q = new F) {} }
class F { function __construct($r = [] + 1) {} }
function h($x, $y = new E) {}
try { h(7); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n", $e->getTraceAsString(), "\n"; }

// arithmetic on literal arrays and strings runs, numeric strings fold
function f($r = [] + 1) { var_dump($r); }
try { f(); } catch (Throwable $e) { echo $e->getMessage(), "\n"; }
function g($r = [1] + [2, 3], $s = "5" + 2, $t = 1 + 2 * 3, $u = E_ALL & ~E_NOTICE) { var_dump($r, $s, $t, $u); }
g();
function k($r = "abc" * 2) { var_dump($r); }
try { k(); } catch (Throwable $e) { echo $e->getMessage(), "\n"; }
set_error_handler(function ($no, $str, $file, $line) { echo "warning: $str on line $line\n"; });
function i($r = "5 apples" + 1) { var_dump($r); }
i();
echo (new ReflectionFunction('g'))->getParameters()[1], "\n";
echo (new ReflectionFunction('i'))->getParameters()[0], "\n";
