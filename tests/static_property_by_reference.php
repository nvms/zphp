<?php
// a static property passed to a by-reference parameter is a reference to it,
// for user functions and built-in ones, from any class reference
function bump(&$r) { $r = 100; return 1; }
class C {
    public static $n = 1; public static $list = [3, 1, 2]; private static $hidden = 'h'; public static $m;
    static function run() { sort(self::$list); bump(static::$n); preg_match('/(\d)/', 'a5', self::$m); self::$hidden .= 'x'; bump(self::$hidden); return [self::$list, self::$n, self::$m, self::$hidden]; }
}
class D extends C { static function more() { bump(parent::$n); return parent::$n; } }
print_r(C::run()); echo D::more(), "\n";
$copy = C::$list; sort(C::$list); array_push(C::$list, 9); print_r(C::$list); print_r($copy);
function byval($v) { $v = 0; } byval(C::$n); echo C::$n, "\n";
try { bump(C::$hidden); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { bump(C::$nope); } catch (Error $e) { echo $e->getMessage(), "\n"; }
$o = new C; bump($o::$n); echo C::$n, "\n";
