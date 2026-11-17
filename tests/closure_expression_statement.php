<?php
// `function () {...};` as a statement is a closure expression
function () { echo "never\n"; };
function &() { static $x; return $x; };
function () use (&$a) { return 1; };
function ($x) { return $x; }   ;
echo "ok\n";
