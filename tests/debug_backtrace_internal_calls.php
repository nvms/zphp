<?php
// debug_backtrace lists the internal functions between user frames, and
// what they call as called from an internal function
function show() { debug_print_backtrace(); var_dump(count(debug_backtrace())); }
array_map(function ($x) { show(); }, [1]);
array_map('show', [1]);
$a = [3, 1];
usort($a, function ($x, $y) { show(); return $x <=> $y; });
call_user_func('show');
call_user_func_array(function () { show(); }, []);
class C { function __toString(): string { show(); return "c"; } function m() { show(); } }
echo new C, "\n";
iterator_to_array((function () { show(); yield 1; })());
$g = (function () { show(); yield 1; })();
foreach ($g as $v) {}
$g = (function () { yield 1; show(); yield 2; })();
$g->current();
$g->next();
(new C)->m();
function lim() { debug_print_backtrace(0, 1); }
array_map('lim', [1]);
var_dump(debug_backtrace());
