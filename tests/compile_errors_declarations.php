<?php
// declarations php's compiler refuses, each compiled in its own process:
// modifiers that don't combine, interface members, parameters, closure
// use lists, static variables, $this, list() keys and nested ternaries
$cases = [
    'abstract class A { abstract final function f(); }',
    'abstract class A { abstract private function f(); }',
    'abstract class A { abstract function f() {} }',
    'class A { const X = 1; const X = 2; }',
    'class A { static const X = 1; }',
    'class A { abstract const X = 1; }',
    'interface I { private const X = 1; }',
    'interface I { protected function f(); }',
    'interface I { function f() {} }',
    'interface I { final function f(); }',
    'interface I { abstract function f(); }',
    'interface I { public $x; }',
    'function f($a, $a) {}',
    'class A { static function f($this) {} }',
    'function f($_GET) {}',
    'function assert($x) {}',
    'class A { function f() { $this = 1; } }',
    'function f() { static $a; static $a; }',
    'function f() { static $this; }',
    '$f = function () use ($this) {};',
    '$f = function () use ($_SERVER) {};',
    '$f = function () use ($a, $a) {};',
    '$f = function ($a) use ($a) {};',
    'foreach ([1] as &$k => $v) {}',
    '[$a, "k" => $b] = [1, 2];',
    'var_dump(1 ? 2 : 3 ? 4 : 5);',
    'var_dump(1 ?: 2 ? 3 : 4);',
    'var_dump(1 ? 2 : 3 ?: 4);',
    'var_dump(0 ?: 0 ?: 3, (1 ? 2 : 3) ? 4 : 5);',
];
foreach ($cases as $code) {
    echo $code, "\n";
    $command = escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -d error_reporting=-1 -r ' . escapeshellarg($code) . ' 2>&1';
    echo trim(shell_exec($command)), "\n\n";
}
