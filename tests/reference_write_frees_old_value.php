<?php
// a write through a reference frees the old value at once, whichever name
// the write used, and `$a = &$b` frees the old value of $a inside the
// assignment (php-src gh10168)

class Noisy {
    public function __construct(public string $name) {}
    public function __destruct() { echo "destruct {$this->name}\n"; }
}

$a = new Noisy('global a');
$b = &$a;
$a = null;
echo "after global write\n";

$a = new Noisy('global b');
$b = &$a;
$GLOBALS['b'] = null;
echo "after \$GLOBALS write\n";

$a = new Noisy('global via function');
$b = &$a;
function clearGlobal() { $GLOBALS['a'] = null; }
clearGlobal();
echo "after function write\n";

function local() {
    $x = new Noisy('local x');
    $y = &$x;
    $x = null;
    echo "after local write\n";
    $x = new Noisy('local y');
    $y = &$x;
    $y = 1;
    echo "after local write through other name\n";
}
local();

class ClearsA {
    public function __destruct() { echo "clearing a\n"; $GLOBALS['a'] = null; }
}
unset($a, $b);
$a = new ClearsA;
$tmp = new ClearsA;
var_dump($a = &$tmp);
var_dump($a, $tmp);

class Box { public $value; }
class ClearsBox {
    public function __destruct() {
        echo "clearing box ", spl_object_id($this), "\n";
        global $box;
        $box->value = null;
    }
}
function bindToBox($box) {
    $tmp = new ClearsBox;
    var_dump($box->value = &$tmp);
}
$box = new Box();
$box->value = new ClearsBox;
bindToBox($box);
bindToBox($box);

class UnsetsA {
    public function __destruct() { unset($GLOBALS['a']); }
}
function returnsValue() { return 42; }
$a = new UnsetsA;
var_dump(@($a =& returnsValue()));
echo "done\n";
