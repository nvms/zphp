<?php
// ++$c[k] and --$c[k] fetch the element for writing once, as $c[k]++ does:
// an ArrayAccess object's offsetGet value is stepped as a temporary (with
// php's notice, and no offsetSet), and a missing array element warns

class C implements ArrayAccess {
    public $d = ['k' => 1];
    function offsetExists($o): bool { echo "exists($o)\n"; return true; }
    function offsetGet($o): mixed { echo "get(", var_export($o, true), ")\n"; return $this->d[$o] ?? 100; }
    function offsetSet($o, $v): void { echo "set(", var_export($o, true), ", $v)\n"; $this->d[$o ?? 'n'] = $v; }
    function offsetUnset($o): void { echo "unset($o)\n"; }
}

$c = new C;
var_dump(++$c['k']);
var_dump($c['k']++);
var_dump(--$c['k']);
var_dump($c['k']--);
var_dump($c['k'] += 5);
var_dump($c['k']);

$a = [];
var_dump($a['x']++, ++$a['y'], $a['z']--, --$a['w']);
var_dump($a);

function steps() {
    $a = ['k' => 1, 'big' => PHP_INT_MAX, 'small' => PHP_INT_MIN];
    $r = &$a['k'];
    for ($i = 0; $i < 3; $i++) {
        ++$a['k'];
        --$a['k'];
        ++$a['k'];
    }
    var_dump($r, ++$a['big'], --$a['small']);
    $m = ['a' => 'y', 'n' => null];
    var_dump(++$m['a'], ++$m['a'], --$m['n'], ++$m['n']);
    $nested = ['a' => ['b' => 1]];
    var_dump(++$nested['a']['b'], --$nested['a']['b'], $nested);
}
steps();

$s = "abc";
try {
    ++$s[0];
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
class RefAccess implements ArrayAccess {
    private $container = array();
    public function offsetSet($offset, $value): void { echo "set\n"; $this->container[$offset] = $value; }
    public function offsetExists($offset): bool { return isset($this->container[$offset]); }
    public function offsetUnset($offset): void { unset($this->container[$offset]); }
    public function &offsetGet($offset): mixed {
        $result = null;
        if (isset($this->container[$offset])) $result = &$this->container[$offset];
        return $result;
    }
}
$o = new RefAccess;
$o['x'] = 1;
var_dump(++$o['x']);
var_dump($o['x']++);
var_dump(--$o['x']);
var_dump($o['x']--);
echo $o['x'], "\n";
var_dump(++$o['missing'], $o['missing']);
$o['s'] = 'a';
var_dump(++$o['s'], $o['s']);
