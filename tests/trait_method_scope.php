<?php
// a class gets its own copy of each trait method: self, __CLASS__ and
// parent name the class the copy belongs to, errors and traces name the
// method as the class has it, and its static variables are its own

trait Hello {
    public function hello() {
        echo __CLASS__, "\n";
        if (get_parent_class(__CLASS__) !== false) parent::hello();
    }
}
class ParentClass { use Hello; }
class ChildClass extends ParentClass { use Hello; }
(new ChildClass)->hello();

trait Foo {
    static $test;
    public static function fooSelf() { return self::class; }
}
trait Bar {
    public static function barSelf() { return self::class; }
    public static function barStatic() { return static::class; }
}
class A { use Foo; use Bar; }
class B extends A { use Foo; }
echo B::fooSelf(), " ", B::barSelf(), " ", B::barStatic(), " ", A::barSelf(), "\n";

trait Typed {
    public function ret(): int { return "x"; }
    public function arg(int $x) {}
}
class UsesTyped { use Typed; }
try { (new UsesTyped)->ret(); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { (new UsesTyped)->arg("x"); } catch (TypeError $e) { echo preg_replace('/, called in .*/', '', $e->getMessage()), "\n"; }

trait Traced {
    public function inner() { echo (new Exception)->getTraceAsString() === '' ? '' : implode("\n", array_map(fn($f) => $f['class'] . $f['type'] . $f['function'], (new Exception)->getTrace())), "\n"; }
    public function outer() { $this->renamed(); }
}
class UsesTraced { use Traced { inner as renamed; } }
(new UsesTraced)->outer();

trait Counter {
    public function next() { static $n = 0; return ++$n; }
}
class CountA { use Counter; }
class CountB { use Counter; }
$a = new CountA; $b = new CountB;
echo $a->next(), $a->next(), $b->next(), "\n";

trait Attributed {
    #[Deprecated("use other()")]
    public function old() {}
}
class UsesAttributed { use Attributed { old as older; } }
var_dump(count((new ReflectionMethod('UsesAttributed', 'older'))->getAttributes()));
echo (new ReflectionMethod('UsesAttributed', 'older'))->getDeclaringClass()->getName(), "\n";
