<?php
// making a partial application compiles a closure carrying the callee's
// types, which deprecates `_` as a type name again, once per call site
set_error_handler(function ($no, $msg, $file, $line) {
    echo "$line: $msg\n";
    return true;
});
eval('function f(_ $a, int|_ $b = 1): ?_ { return null; }');
for ($i = 0; $i < 2; $i++) {
    $f = f(?);
}
function g() { return f(?, 2); }
g();
g();
$h = f(...);
echo "done\n";
