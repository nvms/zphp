<?php
// the value eval() returns is held once, by whoever takes it: a function's
// eval result is freed when nothing holds it, so its handle is reused
class Tracked {
    public function __construct(public string $name) {}
    public function __destruct() { echo "destruct {$this->name}\n"; }
}

function discard() { eval('return new Tracked("discarded");'); echo "discard end\n"; }
discard();
echo "after discard\n";

function keep() { $x = eval('return new Tracked("kept");'); echo "keep end\n"; }
keep();
echo "after keep\n";

function pass() { return eval('return new Tracked("passed");'); }
pass();
echo "after pass\n";

function local() { eval('$o = new Tracked("local");'); echo "local end\n"; }
local();
echo "after local\n";

function anon() {
    static $i = 0;
    return eval(sprintf('return new class { private $prop%s; };', ++$i));
}
var_dump(anon());
var_dump(anon());

function mk() { return eval('return new stdClass;'); }
var_dump(mk());
var_dump(mk());
$held = mk();
var_dump(mk());

$closure = (function () { return eval('return function () { return "closure"; };'); })();
echo $closure(), "\n";
var_dump((function () { return eval('return [new stdClass];'); })());
echo eval('return "string";'), "\n";
echo "end\n";
