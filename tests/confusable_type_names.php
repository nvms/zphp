<?php
// integer, double, boolean and resource in a type are class names, with
// php's compile warning unless the name was imported

function run(string $code): void
{
    $file = tempnam(sys_get_temp_dir(), 'ctn');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -d fatal_error_backtraces=0 ' . escapeshellarg($file) . ' 2>&1');
    unlink($file);
    echo trim(str_replace($file, 'FILE', $out)), "\n";
}

run('function f(integer $x) {} try { f(1); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }');
run('function f(Double|Boolean $x): resource {}');
run('namespace N; function f(boolean $x) {} function g(\integer $x) {} use foo\double; function h(double $x) {}');
run('class integer {} function f(integer $x) { return get_class($x); } echo f(new integer), "\n";');
