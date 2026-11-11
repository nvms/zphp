<?php
// each fiber has its own error_reporting: an @ outside a fiber does not
// silence it, and one inside it ends where the fiber suspends

function suspend_with_warnings(): void {
    trigger_error("silenced inside", E_USER_WARNING);
    Fiber::suspend();
    trigger_error("silenced after resume", E_USER_WARNING);
}

$fiber = new Fiber(function (): void {
    @suspend_with_warnings();
});
$fiber->start();
trigger_error("shown between", E_USER_WARNING);
$fiber->resume();

$outer = new Fiber(function (): void {
    trigger_error("shown in a fiber started under @", E_USER_WARNING);
    Fiber::suspend();
    trigger_error("shown after resume under @", E_USER_WARNING);
});
@$outer->start();
@$outer->resume();
trigger_error("shown at the end", E_USER_WARNING);
