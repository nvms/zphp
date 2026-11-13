<?php
// the assert.* settings: their startup deprecations, assert_options()
// reading and replacing the callback, and an exception from the callback
// when bail is on

function child(array $ini, string $code): void {
    $cmd = escapeshellarg(PHP_BINARY) . ' -n -d error_reporting=-1 -d display_errors=1';
    foreach ($ini as $k => $v) $cmd .= ' -d ' . escapeshellarg("$k=$v");
    $cmd .= ' -r ' . escapeshellarg($code) . ' 2>&1';
    echo str_replace(PHP_BINARY, 'php', shell_exec($cmd)), "---\n";
}

child(['assert.exception' => '0', 'assert.callback' => 'f1', 'assert.active' => 'off', 'assert.bail' => '0', 'assert.warning' => '1'], 'echo "ran\n";');
child(['assert.bail' => 'yes', 'assert.warning' => 'off'], 'echo "ran\n";');
child(['assert.callback' => 'f1', 'assert.exception' => '0'], '
function f1() { echo "f1 called\n"; }
function f2() { echo "f2 called\n"; }
var_dump(@assert_options(ASSERT_CALLBACK));
assert(false);
var_dump(@assert_options(ASSERT_CALLBACK, null));
var_dump(@assert_options(ASSERT_CALLBACK));
assert(false);
@ini_set("assert.callback", "f2");
var_dump(@assert_options(ASSERT_CALLBACK));
assert(false);
var_dump(@assert_options(ASSERT_ACTIVE), @assert_options(ASSERT_WARNING, "0"), @assert_options(ASSERT_WARNING));
try { @assert_options(99); } catch (ValueError $e) { echo $e->getMessage(), "\n"; }
');
child([], '
@assert_options(ASSERT_EXCEPTION, 0);
@assert_options(ASSERT_BAIL, 1);
@assert_options(ASSERT_CALLBACK, function () { throw new Exception("Boo"); });
assert(false);
echo "not reached\n";
');
