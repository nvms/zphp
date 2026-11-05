<?php
// an interface's parents must exist when it is declared, so one that
// extends itself, or two that extend each other, is an error, not a loop

try {
    if (true) {
        interface SelfExtending extends SelfExtending {}
    }
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

try {
    if (true) {
        interface LoopA extends LoopB {}
        interface LoopB extends LoopA {}
    }
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

var_dump(interface_exists('SelfExtending', false), interface_exists('LoopA', false));

interface Base {}
interface Child extends Base {}
class Impl implements Child {}
var_dump(new Impl instanceof Base);
