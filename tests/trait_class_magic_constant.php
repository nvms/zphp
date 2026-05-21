<?php
// regression: __CLASS__ inside a trait method must resolve to the class that
// uses the trait, not the trait itself. zphp baked the compile-time class
// (the trait name) so whoAmI() wrongly returned "HasName" instead of "User".
trait HasName {
    public function whoAmI() { return __CLASS__; }
    public function traitName() { return __TRAIT__; }
    public function methodName() { return __METHOD__; }
    public static function staticWho() { return __CLASS__; }
}

class User { use HasName; }
class Admin { use HasName; }

echo (new User)->whoAmI(), "\n";       // User
echo (new Admin)->whoAmI(), "\n";      // Admin
echo (new User)->traitName(), "\n";    // HasName
echo (new User)->methodName(), "\n";   // HasName::methodName
echo User::staticWho(), "\n";          // User
echo Admin::staticWho(), "\n";         // Admin

// __CLASS__ resolves to the using class even when called on a subclass -
// it is the defining class, not the late-static-bound runtime class
trait Marker { public function mark() { return __CLASS__; } }
class Base { use Marker; }
class Derived extends Base {}

echo (new Derived)->mark(), "\n";      // Base
echo get_class(new Derived), "\n";     // Derived

// __CLASS__ outside any class is still the empty string
function plain() { return __CLASS__; }
var_dump(plain() === "");              // true
