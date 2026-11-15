<?php
// each @ keeps the level it found and puts it back at its end, unless
// error_reporting() set one inside it; an exception leaving @ regions ends
// them the same way, and a fiber has its own level

error_reporting(E_ALL & ~E_DEPRECATED);

function foo($arg) {
    echo @$nonex_foo;
}

function bar() {
    echo @$nonex_bar;
    throw new Exception("test");
}

function foo1() {
    echo $undef1;
    error_reporting(E_ALL);
    echo $undef2;
}

try {
    @foo(@bar(@foo1()));
} catch (Exception $e) {
}
var_dump(error_reporting());

error_reporting(E_ALL & ~E_DEPRECATED);
function foo3() {
    error_reporting(E_ALL);
    echo $undef3;
    throw new Exception("test");
}
try {
    @foo(@foo(@foo3()));
} catch (Exception $e) {
}
var_dump(error_reporting());

error_reporting(E_ALL & ~E_DEPRECATED);
function baz() {
    echo @$blah;
    echo $undef4;
}
function qux() {
    echo @$undef;
    error_reporting(E_ALL);
    echo $blah;
    return baz();
}
@qux();
var_dump(error_reporting());

error_reporting(E_ALL);
function make_exception() {
    @$blah;
    error_reporting(0);
    throw new Exception();
}
try {
    @make_exception();
} catch (Exception $e) {}
var_dump(error_reporting());
error_reporting(E_ALL & ~E_NOTICE);
try {
    @make_exception();
} catch (Exception $e) {}
var_dump(error_reporting());

// inside @ the level has only the fatal errors, which handlers see
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) {
    echo "handler: $msg, level ", error_reporting(), "\n";
    return true;
});
echo @$silenced, $loud;
restore_error_handler();

// error_reporting() changes the ini value; @ doesn't
var_dump(@ini_get('error_reporting'));
error_reporting(E_ALL & ~E_NOTICE);
var_dump(ini_get('error_reporting'));
ini_set('error_reporting', (string) E_ERROR);
var_dump(error_reporting());

// a fiber starts at the ini's level and keeps its own
ini_set('error_reporting', (string) E_ALL);
$f = new Fiber(function () {
    var_dump(error_reporting());
    error_reporting(E_WARNING);
    Fiber::suspend();
    var_dump(error_reporting());
    echo @$in_fiber;
    Fiber::suspend();
    var_dump(error_reporting());
});
@$f->start();
var_dump(error_reporting());
$f->resume();
var_dump(error_reporting());
$f->resume();

// an uncaught exception inside @ in a fiber leaves the resumer's level alone
$g = new Fiber(function () {
    @(function () { throw new Exception("in fiber"); })();
});
try {
    $g->start();
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
var_dump(error_reporting());
echo "Done\n";
