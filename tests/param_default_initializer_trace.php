<?php
// a parameter default php evaluates at the call (RECV_INIT) runs in the
// callee's frame: its trace entry is the call, with the arguments passed
class Probe {
    public function __construct() {
        echo (new Exception)->getTraceAsString(), "\n";
    }
}

function withObject($p, $a = new Probe) { echo "body\n"; }
withObject(7);
withObject('passed', new stdClass);

$closure = function ($z, $a = new Probe) {};
$closure(3);

array_map('withObject', [9]);

function badOffset($a = array()[array()]) {}
function badOffsetLater($x, $y, $a = [1][[]]) {}
foreach (['badOffset', 'badOffsetLater'] as $f) {
    try {
        $f(1, 2);
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n", $e->getTraceAsString(), "\n";
    }
}

function nested($a = new Probe) {}
function outer($b = null) { nested(); }
outer();
