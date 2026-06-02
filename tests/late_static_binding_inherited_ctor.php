<?php

// static::class (late static binding) must resolve to the INSTANTIATED class,
// not the class that defines the constructor being run, across every
// instantiation path: `new Class`, `new $dynamic`, and ReflectionClass::
// newInstance / newInstanceArgs. when a class inherits its constructor from an
// ancestor (and that ancestor calls parent::__construct), static::class inside
// the whole chain stays the leaf class. this is the Symfony Console shape:
// SchedulePauseCommand (no own ctor) -> Illuminate Command::__construct ->
// parent Symfony Command::__construct reads new ReflectionClass(static::class)
// to find its own #[AsCommand] attribute; a wrong static::class made the name
// empty and 500'd every artisan command.

class Root
{
    public ?string $tag = null;

    public function __construct()
    {
        $this->tag = static::class;
    }

    public function getTag(): ?string
    {
        return $this->tag;
    }
}

class Middle extends Root
{
    public function __construct()
    {
        parent::__construct();
    }
}

class Leaf extends Middle {}

$cls = Leaf::class;

echo "new Leaf: ";
var_dump((new Leaf())->getTag());

echo "new \$dynamic: ";
var_dump((new $cls())->getTag());

$rc = new ReflectionClass(Leaf::class);
echo "newInstance: ";
var_dump($rc->newInstance()->getTag());

echo "newInstanceArgs: ";
var_dump($rc->newInstanceArgs([])->getTag());

// inherited typed-property defaults must survive reflection instantiation too:
// the parent's typed array default is deep-cloned per instance, not left null
class HasTypedDefaults
{
    public array $items = [];
    public ?string $note = null;
    public int $n = 5;
}
class ChildTyped extends HasTypedDefaults {}

$o = (new ReflectionClass(ChildTyped::class))->newInstance();
echo "reflected inherited array default: ";
var_dump($o->items);
echo "reflected inherited int default: ";
var_dump($o->n);
