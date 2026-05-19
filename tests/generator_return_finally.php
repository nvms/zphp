<?php
// regression: a 'return' inside a generator's try/finally fires the finally
// block before the generator transitions to completed. previously zphp's
// compiler emitted generator_return without first emitting the finally
// bytecode, so the finally was silently skipped (regular function returns
// already did this correctly)
$log = [];
function tf(&$log) {
    try {
        yield 1;
        yield 2;
        return 'normal';
    } finally {
        $log[] = 'fin';
    }
}
$g = tf($log);
foreach ($g as $_) {}
print_r($log);
echo $g->getReturn() . "\n";

// nested try/finally - both fire
$log = [];
function nested(&$log) {
    try {
        try {
            yield 1;
            return 'r';
        } finally {
            $log[] = 'inner';
        }
    } finally {
        $log[] = 'outer';
    }
}
$g = nested($log);
foreach ($g as $_) {}
print_r($log);
echo $g->getReturn() . "\n";
