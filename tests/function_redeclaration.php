<?php
// a function declared twice names where it was first declared
function make() {
    function helper() { return 1; }
}
make();
echo helper(), "\n";
make();
echo "not reached\n";
