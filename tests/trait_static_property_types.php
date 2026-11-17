<?php
// a class using a trait takes its static properties' types and visibility;
// on the trait itself self keeps its written name in messages

trait T {
    public static self $p;
    public static ?int $n = null;
    private static int $hidden = 1;
    public static function hidden() { return self::$hidden; }
}
class B { use T; }

try { @T::$p = new stdClass; } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { B::$p = new stdClass; } catch (TypeError $e) { echo get_class($e), "\n"; }
B::$p = new B;
var_dump(B::$p instanceof B);
try { B::$n = "x"; } catch (TypeError $e) { echo get_class($e), "\n"; }
B::$n = "42";
var_dump(B::$n);
try { var_dump(B::$hidden); } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump(B::hidden());
