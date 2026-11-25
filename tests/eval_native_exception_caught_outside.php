<?php
// an exception a native throws inside eval'd code is caught by the try
// around the eval, at the top level of the script too
try { eval("intdiv(1, 0);"); } catch (\Throwable $t) { echo get_class($t), ": ", $t->getMessage(), "\n"; }
try { var_dump(eval("return intdiv(1, 0);")); } catch (\Throwable $t) { echo get_class($t), "\n"; }
try { eval("return strlen();"); } catch (\Throwable $t) { echo get_class($t), ": ", $t->getMessage(), "\n"; }
foreach (['intdiv(1, 0)', 'intdiv(4, 2)', 'str_repeat("x", -1)', 'intdiv(6, 2)'] as $e) {
    try { var_dump(eval("return $e;")); } catch (\Throwable $t) { echo get_class($t), ": ", $t->getMessage(), "\n"; }
}
try {
    eval('function thrower() { return intdiv(1, 0); }');
    thrower();
} catch (DivisionByZeroError $e) {
    echo "caught from a function eval declared\n";
}
try {
    eval('try { intdiv(1, 0); } finally { echo "finally in eval\n"; }');
} catch (DivisionByZeroError $e) {
    echo "caught after finally\n";
}
echo "done\n";
