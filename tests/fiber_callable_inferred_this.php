<?php
// a Fiber's callable is resolved where the fiber is made: [A::class, 'm'],
// "A::m" or [self::class, 'priv'] inside a method of A call m on that $this,
// which the fiber holds until its function ends or the fiber goes
class A {
    public ?Fiber $fiber = null;

    public function __construct(public string $name) {}

    public function m() {
        echo "m on {$this->name}\n";
    }

    private function priv() {
        echo "priv on {$this->name}\n";
    }

    public static function st() {
        echo "static, called as ", static::class, "\n";
    }

    public function waits() {
        Fiber::suspend();
        echo "resumed on {$this->name}\n";
    }

    public function make(string $method) {
        return new Fiber([A::class, $method]);
    }

    public function makeFromString() {
        return new Fiber("A::m");
    }

    public function makePrivate() {
        return new Fiber([self::class, 'priv']);
    }

    public function makeOwnPrivate() {
        return new Fiber([$this, 'priv']);
    }

    public function makeStatic() {
        return new Fiber([static::class, 'st']);
    }

    public function keep() {
        $this->fiber = new Fiber([A::class, 'm']);
    }

    public function __destruct() {
        echo "released {$this->name}\n";
    }
}

class B extends A {}

echo "-- started after its creator's last reference went\n";
$fiber = (new A("a1"))->make('m');
$fiber->start();
echo "after start\n";

echo "-- a string callable\n";
$fiber = (new A("a2"))->makeFromString();
$fiber->start();
echo "after start\n";

echo "-- a private method through self::class\n";
$fiber = (new A("a3"))->makePrivate();
$fiber->start();
echo "after start\n";

echo "-- a private method through \$this\n";
$fiber = (new A("a4"))->makeOwnPrivate();
$fiber->start();
echo "after start\n";

echo "-- a static method through static::class\n";
$fiber = (new B("b1"))->makeStatic();
$fiber->start();
echo "after start\n";

echo "-- never started, released with the fiber\n";
$fiber = (new A("a5"))->make('m');
unset($fiber);
echo "after unset\n";

echo "-- suspended while its object has no other reference\n";
$a = new A("a6");
$fiber = $a->make('waits');
$fiber->start();
unset($a);
echo "suspended\n";
$fiber->resume();
echo "after resume\n";

echo "-- a suspended fiber destroyed\n";
$a = new A("a7");
$fiber = $a->make('waits');
$fiber->start();
unset($a);
unset($fiber);
echo "after unset\n";

echo "-- a cycle through the fiber is collected\n";
$a = new A("a8");
$a->keep();
unset($a);
var_dump(gc_collect_cycles() > 0);
echo "end\n";
