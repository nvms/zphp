<?php
// reading an element of a temporary array frees the array right away: the
// objects only it held go before the rest of the expression runs

class A
{
    public function make()
    {
        return new stdClass();
    }
}

class Noisy
{
    public function __construct(public string $name) {}
    public function __destruct()
    {
        echo "destruct {$this->name}\n";
    }
}

function pair()
{
    return [new A(), new A()];
}

function noisy()
{
    return [new Noisy('first'), new Noisy('second')];
}

var_dump(pair()[0]->make());
var_dump(pair()[1]);
$x = pair()[0]->make();
var_dump($x);
unset($x);

$f = (new ReflectionFunction('iterator_to_array'))->getClosure();
$r = new ReflectionMethod($f, '__invoke');
var_dump((string) $r->getParameters()[0]->getType());
var_dump(new stdClass());

$kept = noisy()[0];
echo "kept {$kept->name}\n";
unset($kept);
echo "next\n";
