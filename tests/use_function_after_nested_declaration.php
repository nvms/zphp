<?php
// a function declared inside a statement is seen by a later use function
if (false) {
    function foo() {
    }
}

use function bar\foo;

echo "not reached\n";
