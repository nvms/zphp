<?php
// unset() fetches a static property container for unsetting: an
// uninitialized typed property is no error, an undeclared one is
class C {
    public static object $u;
    public static ?object $n;
    private static object $priv;
    public static $plain;
    public private(set) static object $ps;
    public private(set) static array $pa;
    public private(set) static int $pi = 1;
    public private(set) static array $pfull = ['a' => 1];
}
unset(C::$u->foo);
unset(C::$u->foo->bar);
unset(C::$u['x']);
unset(C::$plain->foo);
unset(C::$ps->foo);
unset(C::$pa['x']);
echo "ok\n";
try { unset(C::$nope->foo); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { unset(C::$priv->foo); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { unset(D::$x->foo); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { unset(C::$nope['a']); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { unset(C::$priv['a']); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { unset(C::$pi->foo); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { unset(C::$pfull['a']); } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump(C::$pfull);
C::$u = new stdClass;
C::$u->foo = 1;
C::$u->bar = 2;
unset(C::$u->foo);
var_dump(C::$u);
$c = 'C';
unset($c::$u->bar);
var_dump(C::$u);
