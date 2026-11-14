<?php
// ArrayObject's sort methods call the array function of the same name, so
// with that function disabled they throw. disable_functions is a startup
// setting, so the calls run in a child process

$code = <<<'PHP'
$ao = new ArrayObject(['b' => 2, 'a' => 1, 'c' => 3]);
foreach (['asort', 'ksort', 'natsort', 'natcasesort'] as $m) {
    try {
        $ao->$m();
        echo "$m ok: ", implode(',', array_keys($ao->getArrayCopy())), "\n";
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
foreach (['uasort', 'uksort'] as $m) {
    try {
        $ao->$m(fn($x, $y) => $x <=> $y);
        echo "$m ok\n";
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
try {
    $ao->asort("not a flag");
} catch (Throwable $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
PHP;

echo shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d disable_functions=asort,uksort,natsort -r ' . escapeshellarg($code) . ' 2>&1');
echo shell_exec(escapeshellarg(PHP_BINARY) . ' -n -r ' . escapeshellarg($code) . ' 2>&1');
