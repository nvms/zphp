<?php
// a throw inside a destructor (or any nested call) never takes a throwable
// its caller holds on the operand stack as the exception a finally rethrows
class Cleanup {
    function __destruct() {
        try {
            throw new LogicException('inner');
        } catch (LogicException $e) {
            echo 'caught ', $e->getMessage(), ', previous: ', $e->getPrevious() ? get_class($e->getPrevious()) : 'none', "\n";
        }
    }
}
function show(Throwable $held, $value) { echo get_class($held), ' ', $held->getMessage(), ' ', $value, "\n"; }
show(new RuntimeException('held'), (function () { new Cleanup; return 1; })());
function rethrow() {
    try {
        throw new RuntimeException('first');
    } finally {
        echo "finally\n";
    }
}
try { rethrow(); } catch (RuntimeException $e) { echo 'caught ', $e->getMessage(), "\n"; }
