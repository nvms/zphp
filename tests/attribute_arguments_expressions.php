<?php
// attribute arguments are constant expressions php evaluates each time
// reflection asks, in the scope of the class the attribute is on
#[Attribute(Attribute::TARGET_ALL | Attribute::IS_REPEATABLE)]
class Meta {
    function __construct(public $value = null, public $other = null) {}
}
class Tag { function __construct(public $v = 1) { echo "Tag constructed\n"; } }
class Base { protected const KIND = 'base'; }
const GLOBAL_NAME = 'global';

#[Meta(parent::KIND)]
#[Meta(self::OWN)]
#[Meta(new Tag(2))]
#[Meta(other: [1, 'k' => GLOBAL_NAME . '!'], value: self::class)]
#[Meta(Base::class)]
#[Meta(PHP_INT_SIZE * 2)]
class Target extends Base {
    const OWN = 'own';
    #[Meta(self::OWN . '-method')]
    function m(#[Meta(parent::KIND)] $p) {}
    #[Meta(new Tag)]
    public $prop;
    #[Meta(self::OWN)]
    const C = 1;
}

#[Meta(parent::KIND)]
class Orphan {}

#[Meta(self::X)]
function plain() {}

function show(array $attrs) {
    foreach ($attrs as $a) {
        try { var_dump($a->getArguments()); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
    }
}
echo "declared\n";
$r = new ReflectionClass('Target');
show($r->getAttributes());
show($r->getMethod('m')->getAttributes());
show($r->getMethod('m')->getParameters()[0]->getAttributes());
show($r->getProperty('prop')->getAttributes());
show($r->getReflectionConstant('C')->getAttributes());
show((new ReflectionClass('Orphan'))->getAttributes());
show((new ReflectionFunction('plain'))->getAttributes());
$first = $r->getAttributes()[2]->newInstance();
$second = $r->getAttributes()[2]->newInstance();
var_dump($first->value === $second->value);
