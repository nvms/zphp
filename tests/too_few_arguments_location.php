<?php
function needs($a, $b) {}
class K { function m($x) {} static function s($y) {} }
foreach ([fn() => needs(1), fn() => (new K)->m(), fn() => K::s(), fn() => call_user_func('needs', 1), fn() => array_map('needs', [1])] as $f) {
    try { $f(); } catch (ArgumentCountError $e) { echo $e->getLine(), " ", $e->getMessage(), "\n", $e->getTraceAsString(), "\n"; }
}
