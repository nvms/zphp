<?php
// regression: ReflectionClassConstant exposes only 'name' and 'class' as
// public properties (value looked up on demand from the class table) and
// implements getModifiers() returning the PHP-format bitmask:
// IS_PUBLIC=1, IS_PROTECTED=2, IS_PRIVATE=4, IS_FINAL=32
class Demo {
    public const PUB = "p";
    protected const PRO = "r";
    private const PRI = "v";
    final public const FIN = "f";
}

$r = new ReflectionClass(Demo::class);
foreach ($r->getReflectionConstants() as $rc) {
    echo $rc->getName() . "=" . var_export($rc->getValue(), true)
        . " mods=" . $rc->getModifiers()
        . " pub=" . ($rc->isPublic() ? 'y' : 'n')
        . " pri=" . ($rc->isPrivate() ? 'y' : 'n')
        . " final=" . ($rc->isFinal() ? 'y' : 'n')
        . "\n";
}

// print_r shows only name + class, no internal value slot
$pub = $r->getReflectionConstant('PUB');
print_r($pub);

// getValue still works after print_r access
echo "v=" . $pub->getValue() . "\n";
