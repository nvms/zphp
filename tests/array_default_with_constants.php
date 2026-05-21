<?php
// regression: a function parameter default that is an array literal containing
// constant references resolves each element. previously the elements stayed as
// raw deferred-constant sentinels and printed as garbage.
const PREFIX = "pre_";
const NUM = 10;
define('DYN', 'dynamic');

function listDefault($x = [PREFIX, NUM, DYN]) { return $x; }
print_r(listDefault());

function keyedDefault($x = ['p' => PREFIX, 'n' => NUM]) { return $x; }
print_r(keyedDefault());

function nestedDefault($x = [[PREFIX], ['n' => NUM]]) { return $x; }
print_r(nestedDefault());

// plain literal arrays still work
function plainDefault($x = [1, 'two', 3.5, true, null]) { return $x; }
print_r(plainDefault());

// a constant used as an array key
function keyConst($x = [PREFIX => 'value']) { return $x; }
print_r(keyConst());

// passing an explicit argument bypasses the default
print_r(listDefault(['explicit']));

// empty array default unaffected
function emptyDefault($x = []) { return $x; }
var_dump(emptyDefault());

// a bare constant default still works
function bareConst($x = PREFIX) { return $x; }
echo bareConst(), "\n";
