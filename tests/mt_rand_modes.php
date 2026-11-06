<?php
// mt_srand and Random\Engine\Mt19937 in both of php's modes; MT_RAND_PHP is
// deprecated and reloads and scales as php's legacy generator did
error_reporting(E_ALL);
set_error_handler(function ($l, $m) { echo "[$l] $m
"; return true; });
mt_srand(1); echo mt_rand(), " ", mt_rand(1, 100), " ", rand(), "\n";
var_dump(MT_RAND_MT19937, MT_RAND_PHP);
mt_srand(5, MT_RAND_MT19937); echo mt_rand(), "\n";
mt_srand(5, MT_RAND_PHP); for ($i = 0; $i < 700; $i++) mt_rand(); echo mt_rand(), " ", mt_rand(1, 1000), " ", rand(10, 1), "\n";
srand(3); echo rand(), " ", rand(5, 10), "\n";
mt_srand(7, 99); echo mt_rand(1, 6), "\n";
$e = new Random\Engine\Mt19937(3, MT_RAND_PHP); for ($i = 0; $i < 700; $i++) $e->generate(); echo bin2hex($e->generate()), "\n";
try { new Random\Engine\Mt19937(3, 5); } catch (ValueError $e) { echo $e->getMessage(), "\n"; }
mt_srand(11, MT_RAND_PHP); echo mt_rand(PHP_INT_MIN, PHP_INT_MAX) !== null ? "ok\n" : "";
