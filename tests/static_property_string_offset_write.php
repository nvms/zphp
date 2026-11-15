<?php
// a string offset write into a static property writes the property
class C { public static $string = "hello"; public static string $t = "abc"; }
C::$string[0] = "j"; var_dump(C::$string);
C::$t[5] = "z"; var_dump(C::$t);
$r = &C::$string; C::$string[1] = "E"; var_dump($r);
class D extends C { static function f() { static::$string[2] = "L"; self::$t[0] = "A"; } } D::f(); var_dump(C::$string, C::$t);
