<?php
// break outside any loop is a compile-time error
echo "never printed\n";
function f() {
    try {
        break;
    } finally {
    }
}
