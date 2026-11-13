<?php
echo "start\n";
function f($foo) {
    return $foo?->foo->bar(...);
}
