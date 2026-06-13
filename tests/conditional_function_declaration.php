<?php
// covers: PHP's function binding semantics - unconditional top-level
// declarations are hoisted (callable before their line), declarations nested
// in if/else/loops/another function bind at runtime when execution reaches
// them. the function_exists() polyfill pattern depends on this: a guarded
// fallback must not exist when the guard is false or never reached

// top-level declarations hoist, including through bare blocks
echo hoisted(), "\n";
function hoisted() { return 'hoisted'; }
echo hoisted_in_block(), "\n";
{ function hoisted_in_block() { return 'hoisted-in-block'; } }

// branch picks the body at runtime
if (PHP_VERSION_ID >= 80000) {
    function picked() { return 'modern'; }
} else {
    function picked() { return 'legacy'; }
}
echo picked(), "\n";

// the polyfill pattern: guard true defines, guard false leaves undefined
if (!function_exists('poly_a')) {
    function poly_a() { return 'poly_a'; }
}
echo poly_a(), "\n";
var_dump(function_exists('never_a'));
if (false) { function never_a() {} }
var_dump(function_exists('never_a'));

// nested in a function body: bound on first call of the outer, idempotent
// thanks to the guard
function outer_decl() {
    if (!function_exists('inner_decl')) {
        function inner_decl() { return 'inner'; }
    }
    return inner_decl();
}
var_dump(function_exists('inner_decl'));
echo outer_decl(), "\n";
var_dump(function_exists('inner_decl'));
echo outer_decl(), "\n";

// loop bodies are conditional contexts
foreach ([1] as $_) { function in_foreach() { return 'foreach'; } }
echo in_foreach(), "\n";
while (!function_exists('in_while')) { function in_while() { return 'while'; } }
echo in_while(), "\n";

// try is a conditional context too
try { function in_try() { return 'try'; } } catch (\Throwable $e) {}
echo in_try(), "\n";

// conditional declarations after a return guard in a required file must not
// leak (the symfony polyfill bootstrap pattern: define-if-missing AFTER an
// early return when the extension is loaded)
$inc = sys_get_temp_dir() . '/zphp_cond_decl_inc_' . getmypid() . '.php';
file_put_contents($inc, '<?php if (true) { return; } if (!function_exists("after_return_fn")) { function after_return_fn() {} }');
require $inc;
unlink($inc);
var_dump(function_exists('after_return_fn'));
