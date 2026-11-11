<?php
// a protected method that overrides an ancestor's is callable from any
// class the topmost declaration is visible to, as php's
// zend_get_function_root_class decides; a trait's method counts as the
// class's own

class P { protected function common() { echo "P::common\n"; } }
class Sibling extends P { public function test(P $other) { $other->common(); } }
class Overrides extends P { protected function common() { echo "Overrides::common\n"; } }
trait CommonTrait { protected function common() { echo "CommonTrait::common\n"; } }
class FromTrait extends P { use CommonTrait; }
class Deeper extends Overrides { protected function common() { echo "Deeper::common\n"; } }
$s = new Sibling;
$s->test(new Overrides);
$s->test(new FromTrait);
$s->test(new Deeper);

// a method that only the subclass declares stays out of reach
class Q {}
class R extends Q { protected function own() { echo "R::own\n"; } }
class S extends Q { public function test(Q $q) { $q->own(); } }
try { (new S)->test(new R); } catch (Error $e) { echo $e->getMessage(), "\n"; }

// a private ancestor declaration is no prototype
class X { private function m() {} }
class Y extends X { protected function m() { echo "Y::m\n"; } }
class Z extends X { public function test(X $x) { $x->m(); } }
try { (new Z)->test(new Y); } catch (Error $e) { echo $e->getMessage(), "\n"; }
