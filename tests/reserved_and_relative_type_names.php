<?php
// names php refuses while compiling: reserved words as class names, aliases
// and imports, built-in types written qualified, and self/parent where no
// class (or no parent) is in scope. each case runs in its own process

function run(string $code): void
{
    $file = tempnam(sys_get_temp_dir(), 'rtn');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -d fatal_error_backtraces=0 ' . escapeshellarg($file) . ' 2>&1');
    unlink($file);
    echo trim(str_replace($file, 'FILE', $out)), "\n";
}

run('namespace foo; class int {}');
run('class Mixed {}');
run('use foo\bar as string;');
run('use foo\iterable;');
run('class A {} class_alias("A", "Float");');
run('class A {} class_alias("A", "\\\\Bool");');
run('function f(bar\int $a) {}');
run('function f(\iterable $a) {}');
run('namespace n; class A { function m(\self $a) {} }');
run('function f($x): parent {}');
run('function f(self $x) {}');
run('interface I { function f(parent $x); }');
run('class A { function m(): parent {} }');
run('trait T { function m(): parent { return $this; } } echo "trait ok\n";');
run('$f = function (): self {}; echo "closure ok\n";');
run('class P {} class A extends P { function m(parent $x): self { return $this; } } echo "ok\n";');
run('namespace n; function f(namespace\Foo $x) { return $x; } echo "relative class ok\n";');
