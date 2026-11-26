<?php
// in a namespace an unqualified array_map() is resolved when it runs and
// stays a call; \array_map() and an imported one become the loop, and the
// callback's name resolves as a call written there would
namespace Shop;

use function array_map as map;

function frames(\Throwable $e) {
    foreach ($e->getTrace() as $i => $f) {
        echo "  #$i ", $f['function'], " line ", $f['line'] ?? '-', "\n";
    }
}
function thrower($v) { throw new \Exception("t$v"); }
function strrev($s) { return "local:" . $s; }

try { array_map(thrower(...), [1]); } catch (\Exception $e) { echo $e->getMessage(), "\n"; frames($e); }
try { \array_map(thrower(...), [2]); } catch (\Exception $e) { echo $e->getMessage(), "\n"; frames($e); }
try { map(thrower(...), [3]); } catch (\Exception $e) { echo $e->getMessage(), "\n"; frames($e); }
var_dump(\array_map(strrev(...), ['ab']));
var_dump(\array_map(\strrev(...), ['ab']));
var_dump(\array_map(strtoupper(...), ['ab']));
