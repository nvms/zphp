<?php
// get_defined_constants lists constants in the order they were made, and const
// declarations count as user constants
define("ZZ", 1); const AA = 2; define("MM", 3);
var_dump(get_defined_constants(true)["user"]);
$all = get_defined_constants(); $k = array_keys($all); $i = array_search("E_ERROR", $k); var_dump(array_slice($k, $i, 3));
$u = []; foreach (get_defined_constants() as $n => $v) if (str_starts_with($n, "PHP_URL")) $u[] = "$n=$v"; echo implode(" ", $u), "\n";
