<?php
// constants from a trait and in an enum keep their visibility, final flag
// and type, so a using class's checks see them
trait Labels { final public const string NAME = 'labels'; protected const KIND = 'k'; private const int SIZE = 3; }
class UsesLabels { use Labels; }
interface Named { const ?string NAME = null; }
final class Typed implements Named { use Labels; }
enum Suit { final public const WILD = 'joker'; protected const RANK = 1; final public function label() { return 'suit'; } }
foreach (['UsesLabels', 'Suit'] as $class) {
    foreach ((new ReflectionClass($class))->getReflectionConstants() as $r) {
        echo $class, '::', $r->getName(), ' ', implode(' ', Reflection::getModifierNames($r->getModifiers())), ' ', $r->getType() ?? '-', "\n";
    }
}
var_dump((new ReflectionMethod('Suit', 'label'))->isFinal(), Typed::NAME);
echo "declaring\n";
if (true) {
    class Overrides extends UsesLabels { const NAME = 'x'; }
}
