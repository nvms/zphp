<?php
// compile errors php's parser throws are CompileError exceptions the code
// around eval() can catch; __halt_compiler() is one inside a block

function attempt(string $code): void {
    try {
        eval($code);
        echo "compiled\n";
    } catch (CompileError $e) {
        echo get_class($e), ": ", $e->getMessage(), " (line ", $e->getLine(), ")\n";
    }
}

attempt('if (false) { class C { final final function foo() {} } }');
attempt('if (false) { class D { private protected $x; } }');
attempt('if (true) { __HALT_COMPILER(); }');
attempt("function f() {\n    __halt_compiler();\n}");
attempt('while (false) { __halt_compiler(); echo 1; }');
attempt('if (false) { abstract abstract class E {} }');
attempt('echo "fine\n";');
echo "done\n";
