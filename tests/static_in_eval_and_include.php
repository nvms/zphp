<?php
// static variables declared by eval or included code belong to that run
// and bind the variable of the scope the code runs in
function f() { eval(" static \$k = [4]; \$k[] = 1; "); var_dump($k); }
f(); f();
eval(" static \$g = 3; ");
var_dump($g);
function h() { static $a = 1; eval("var_dump(\$a); static \$a = 2; var_dump(\$a);"); var_dump($a); }
h();
var_dump(include __DIR__ . "/include/static_counter.php", include __DIR__ . "/include/static_counter.php");
function inc() { return include __DIR__ . "/include/static_counter.php"; }
var_dump(inc(), inc());
for ($i = 0; $i < 2; $i++) eval(" static \$c = 0; \$c++; var_dump(\$c); ");
