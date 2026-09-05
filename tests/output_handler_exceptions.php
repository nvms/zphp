<?php
foreach (['ob_clean', 'ob_flush', 'ob_end_clean', 'ob_get_clean', 'ob_end_flush', 'ob_get_flush'] as $op) {
    ob_start();
    ob_start(function ($s, $phase) { throw new Exception('handler failed'); });
    echo 'raw';
    try { $op(); echo 'unreachable'; }
    catch (Exception $e) { echo '|', $e->getMessage(), ':', ob_get_level(), ':', ob_get_contents(), '|'; }
    while (ob_get_level() > 1) ob_end_clean();
    $output = ob_get_clean();
    echo $op, '=', $output, "\n";
}
// Internal functions enforce their arity even when called as handlers.
ob_start('strtoupper');
echo 'discard';
try { ob_end_clean(); echo 'unreachable'; }
catch (ArgumentCountError $e) { echo get_class($e), ':', $e->getMessage(), ':', ob_get_level(), "\n"; }
try { strtoupper(); }
catch (ArgumentCountError $e) { echo $e->getMessage(), "\n"; }
echo strtoupper('normal'), "\n";
