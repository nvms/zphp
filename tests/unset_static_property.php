<?php
// unset() of a static property is an Error once the class is found
class C { public static $p = 1; private static $q; }
try { unset(C::$p); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { unset(C::$nope); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { unset(Missing::$p); } catch (Error $e) { echo $e->getMessage(), "\n"; }
class D extends C { static function f() { unset(parent::$p); } }
try { D::f(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump(C::$p);
