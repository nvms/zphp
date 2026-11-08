<?php
// an anonymous class is declared the first time its `new` runs, with its
// attributes, its members' attributes and its modifiers
#[Attribute(Attribute::TARGET_ALL)]
class Mark { function __construct(public $v = null) {} }
interface Shape { function area(); }
abstract class Base { abstract function name(); }
trait Named { public $label = 'named'; function label() { return $this->label; } }

for ($i = 0; $i < 3; $i++) {
    $o = new #[Mark('outer')] class($i) extends Base implements Shape {
        use Named;
        const UNIT = 'cm';
        const FULL = self::UNIT . '2';
        public static $made = 0;
        public string $hooked { get => 'side ' . $this->side; }
        public function __construct(public int $side) { self::$made++; }
        #[Mark(self::FULL)]
        final function area() { return $this->side ** 2 . static::FULL; }
        function name() { return 'square'; }
    };
    echo $o->area(), ' ', $o->name(), ' ', $o->label(), ' ', $o::$made, ' ', $o->hooked, "\n";
}
$r = new ReflectionObject($o);
var_dump($r->getAttributes()[0]->getArguments(), $r->getMethod('area')->getAttributes()[0]->newInstance()->v);
var_dump($r->getMethod('area')->isFinal(), $o instanceof Shape);

$ro = new readonly class(5) { public function __construct(public int $n) {} };
try { $ro->n = 6; } catch (Error $e) { echo get_class($e), "\n"; }
var_dump((new ReflectionClass($ro))->isReadOnly());
