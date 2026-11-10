<?php
// php refuses yield outside a function when compiling, before anything runs
echo "not printed\n";
$x = yield 1;
