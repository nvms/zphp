<?php
// a trait constant's attributes, read on the trait and on a class using it
#[Attribute(Attribute::TARGET_CLASS_CONSTANT)]
class Tag {
    public function __construct(public string $value, public int $weight = 0) {}
}

trait Tagged {
    #[Tag('first', weight: 2)]
    public const FIRST = 1;
    public const PLAIN = 2;
    #[Tag('third')]
    protected const THIRD = 3;
}
trait Outer {
    use Tagged;
}
class UsesTagged {
    use Tagged;
}
class UsesOuter {
    use Outer;
}

foreach (['Tagged', 'UsesTagged', 'UsesOuter'] as $class) {
    $r = new ReflectionClass($class);
    foreach ($r->getReflectionConstants() as $c) {
        $attrs = $c->getAttributes();
        echo $class, '::', $c->getName(), ': ', count($attrs);
        foreach ($attrs as $a) {
            echo ' ', $a->getName(), ' ', json_encode($a->getArguments()), ' ', $a->newInstance()->value;
        }
        echo "\n";
    }
}
var_dump((new ReflectionClassConstant('UsesTagged', 'FIRST'))->getAttributes(Tag::class)[0]->getArguments());
