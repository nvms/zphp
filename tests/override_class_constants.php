<?php
// php 8.6 lets #[\Override] mark a class constant or an enum case: it must
// meet a parent's non-private constant or an interface's
interface I { const C = 3; }
interface J extends I { #[\Override] const C = 4; }
class P { const A = 1; protected const B = 2; }
class K extends P implements I {
    #[\Override] const A = 10;
    #[\Override] protected const B = 20;
    #[\Override] const C = 30;
}
enum E: int implements I {
    #[\Override] case C = 1;
}
trait T { #[\Override] const A = 5; }
class L extends P { use T; }
echo K::A, K::C, J::C, E::C->value, L::A, "\n";
$attrs = (new ReflectionClassConstant(K::class, 'A'))->getAttributes();
echo $attrs[0]->getName(), ' ', $attrs[0]->getTarget() === Attribute::TARGET_CLASS_CONSTANT ? 'constant' : 'other', "\n";
var_dump($attrs[0]->newInstance() instanceof Override);
var_dump((new ReflectionClass(Override::class))->getAttributes()[0]->getArguments());

if (true) {
    class Q { private const X = 1; }
    class R extends Q {
        #[\Override] const X = 2;
    }
}
echo "unreachable\n";
