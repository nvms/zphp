<?php
// what php's compiler refuses in a constant expression (zend_compile_const_expr):
// class constants, property defaults and enum cases take no `new` or object
// cast, parameter defaults and global constants take them, and every context
// refuses calls, variables, dynamic names, non-static closures and the like
$cases = [
    'class C { const X = foo(); }',
    'class C { const X = $a; }',
    'class C { public $p = new stdClass; }',
    'class C { public static $p = new stdClass; }',
    'class C { const X = new stdClass; }',
    'class C { const X = (object) []; }',
    'function f($a = (object) []) { var_dump($a); } f();',
    'const X = new stdClass; var_dump(X);',
    'class C { const X = static::Y; }',
    'class C { const X = static::class; }',
    'class C { const X = [][0]::class; }',
    'class C { const X = "a $b"; }',
    'class C { const X = $a instanceof C; }',
    'class C { const X = @1; }',
    'class C { const X = A::$b; }',
    'const X = [][] ?? 1;',
    'function f($a = new class {}) {}',
    'function f($a = new static) {}',
    'function f($a = new C(...[1])) {}',
    'function f($a = new C(x: 1, 2)) {}',
    'class C { public $p = function () {}; }',
    'function f($a = static function () use ($b) {}) {}',
    'function f($a = fn() => 1) {}',
    'const X = $foo(...);',
    'const X = (Name)(...);',
    'const X = (0)(...);',
    'class C { const X = static::m(...); }',
    'const X = (new C)->m(...);',
    'enum E: int { case A = new stdClass; }',
    'enum E: int { case A = 1 + 1; } var_dump(E::A->value);',
    'class C { const X = (null)?->y; } var_dump(C::X);',
];
foreach ($cases as $code) {
    echo $code, "\n";
    $command = escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -d error_reporting=-1 -r ' . escapeshellarg($code) . ' 2>&1';
    echo trim(shell_exec($command)), "\n\n";
}
