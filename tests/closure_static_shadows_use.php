<?php
// a closure's static variable may not share a name with its use list
function () use ($b) { static $c; };
echo "compiled\n";
eval('function () use (&$a) { static $a; };');
