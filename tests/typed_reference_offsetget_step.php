<?php
// ++/-- through the reference &offsetGet() returns checks the typed
// property the reference is bound to
$a = new class implements ArrayAccess {
    public int $foo = 1;
    public string $s = "5";
    function offsetExists($o): bool { return true; }
    function &offsetGet($o): mixed { if ($o === 's') return $this->s; return $this->foo; }
    function offsetSet($o, $v): void { print "offsetSet($v)\n"; }
    function offsetUnset($o): void {}
};
$a[0]--;
var_dump($a->foo);
var_dump(++$a[0]);
$a->foo = PHP_INT_MIN;
try { $a[0]--; } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
var_dump($a->foo);
try { --$a[0]; } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
var_dump($a->foo);
$a->foo = PHP_INT_MAX;
try { $a[0]++; } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { ++$a[0]; } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
var_dump($a->foo);
var_dump(++$a['s']);
var_dump($a->s);
var_dump($a['s']--);
var_dump($a->s);
