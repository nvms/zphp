<?php
// php 8.5 warns when a NAN is coerced to another type
$nan = fdiv(0, 0);
function implicit_to_bool(bool $v) { var_dump($v); }
function implicit_to_string(string $v) { var_dump($v); }
implicit_to_bool($nan);
implicit_to_string($nan);
var_dump((int) $nan);
var_dump((bool) $nan);
var_dump((string) $nan);
var_dump((array) $nan);
var_dump((object) $nan);
foreach (['null', 'bool', 'int', 'string', 'array', 'object'] as $type) {
    $nan = fdiv(0, 0);
    settype($nan, $type);
    var_dump($nan);
}
$nan = fdiv(0, 0);
if ($nan) echo "truthy\n";
var_dump(!$nan, $nan && true, $nan ? 1 : 2, $nan xor false);
for ($i = 0; $i < 3; $i++) {
    if ($nan) echo "loop $i\n";
}
var_dump((int) 1e42, (int) "1e42");
