<?php
// covers: ReflectionMethod constructor, ReflectionClass with objects, named args in method calls

class Animal {
    public function speak($sound, $volume = 5) { return "$sound at $volume"; }
    protected static function secret() { return "hidden"; }
}

// ReflectionMethod with string args
$rm = new ReflectionMethod('Animal', 'speak');
echo $rm->getName() . "\n";
echo $rm->getNumberOfParameters() . "\n";
echo $rm->getNumberOfRequiredParameters() . "\n";
echo $rm->isPublic() ? "public\n" : "not public\n";

// ReflectionMethod with object
$a = new Animal();
$rm2 = new ReflectionMethod($a, 'speak');
echo $rm2->getName() . "\n";
echo $rm2->getDeclaringClass()->getName() . "\n";

// ReflectionMethod with Class::method string
$rm3 = @new ReflectionMethod('Animal::speak');
echo $rm3->getName() . "\n";

// ReflectionMethod static
$rm4 = new ReflectionMethod('Animal', 'secret');
echo $rm4->isStatic() ? "static\n" : "not static\n";
echo $rm4->isProtected() ? "protected\n" : "not protected\n";

// ReflectionClass with object
$rc = new ReflectionClass($a);
echo $rc->getName() . "\n";

// named args in method calls
class Builder {
    public function config(?string $first = null, ?string $second = null, ?string $third = null) {
        return "first=$first second=$second third=$third";
    }
}
$b = new Builder();
echo $b->config(second: 'B', third: 'C') . "\n";
echo $b->config(third: 'Z', first: 'A') . "\n";
