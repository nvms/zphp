<?php
declare(strict_types=1);
// under strict_types php keeps the array_map() call: the callback is called
// by array_map, in weak mode, and array_map() is in the trace
function frames(Throwable $e) {
    foreach ($e->getTrace() as $i => $f) {
        echo "  #$i ", $f['function'], " line ", $f['line'] ?? '-', "\n";
    }
}
function takes_int(int $i) { return $i * 2; }
function thrower($v) { throw new Exception("t$v"); }
var_dump(array_map(takes_int(...), ['3', 4]));
try { array_map(thrower(...), [7]); } catch (Exception $e) { echo $e->getMessage(), "\n"; frames($e); }
try { array_map(takes_int(...), 'x'); } catch (TypeError $e) { echo $e->getMessage(), "\n"; frames($e); }
