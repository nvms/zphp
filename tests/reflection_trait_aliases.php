<?php
// ReflectionClass::getTraitAliases: alias => "Trait::method" for each `as`
// rule that gives a method a new name

trait T1 { function m1() {} function m2() {} }
trait T2 { function m2() {} function say() {} }

class C1 {}
class C2 { use T1; }
class C3 { use T1 { m1 as a1; } }
class C4 { use T1, T2 { T1::m2 insteadof T2; m1 as protected a1; T2::m2 as a2; say as private talk; m1 as private; } }
class C5 { use T2 { SAY as Shout; } }

foreach (['C1', 'C2', 'C3', 'C4', 'C5'] as $c) {
    echo "$c: ";
    var_dump((new ReflectionClass($c))->getTraitAliases());
}
