<?php
// the cli's $_SERVER: the environment, then the script's names, the request
// time and the arguments, as php's cli registers them

$keys = array_keys($_SERVER);
$env = getenv();
$own = array_values(array_filter($keys, fn($k) => !array_key_exists($k, $env)));
var_dump($own);
var_dump(array_slice($keys, 0, count($env)) === array_keys($env));
foreach ($env as $name => $value) {
    if ($_SERVER[$name] !== $value) echo "differs: $name\n";
}
var_dump($_SERVER['PHP_SELF'] === $_SERVER['SCRIPT_NAME'], $_SERVER['SCRIPT_FILENAME'] === $_SERVER['PATH_TRANSLATED']);
var_dump(basename($_SERVER['SCRIPT_FILENAME']), $_SERVER['DOCUMENT_ROOT']);
var_dump(is_float($_SERVER['REQUEST_TIME_FLOAT']), is_int($_SERVER['REQUEST_TIME']));
var_dump(abs($_SERVER['REQUEST_TIME'] - time()) < 5, (int) $_SERVER['REQUEST_TIME_FLOAT'] === $_SERVER['REQUEST_TIME']);
var_dump($_SERVER['argc'], count($_SERVER['argv']), $_SERVER['argv'] === $argv);
var_dump(isset($_SERVER['REQUEST_METHOD']), isset($_SERVER['HTTP_HOST']), isset($_SERVER['REQUEST_URI']));
