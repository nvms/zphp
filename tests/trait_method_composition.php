<?php
// a class's own method wins over its traits', insteadof picks one of two,
// the same trait reached twice is no collision, and methods keep the order
// the traits declare them in
trait A { function talk() { return 'A'; } function z() {} function a() {} }
trait B { function talk() { return 'B'; } }
trait Wrapper { use A; }
class Own { use A, B; function talk() { return 'own'; } }
class Picked { use A, B { B::talk insteadof A; A::talk as talkA; } }
class Twice { use A, Wrapper; }
echo (new Own)->talk(), (new Picked)->talk(), (new Picked)->talkA(), (new Twice)->talk(), "\n";
print_r(get_class_methods('Twice'));
// a trait's own method wins over one from a trait it uses, and a trait's
// own insteadof rules settle collisions among the traits it uses
trait Inner { function dump() { return 'inner'; } }
trait Outer { use Inner; function dump() { return 'outer'; } }
trait D1 { function f() { return 'D1'; } }
trait D2 { function f() { return 'D2'; } }
trait Combo { use D1, D2 { D1::f insteadof D2; } }
class UsesOuter { use Outer, Combo; }
echo (new UsesOuter)->dump(), (new UsesOuter)->f(), "\n";
