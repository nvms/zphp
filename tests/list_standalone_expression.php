<?php
// list() is only an assignment target
echo "never printed\n";
$x = [list($a)];
