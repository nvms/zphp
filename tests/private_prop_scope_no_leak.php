<?php

// a class's private property must not "leak" onto an unrelated object just
// because the access happens inside that class's method. PHP resolves
// $obj->prop against $obj's OWN class hierarchy; the executing scope only
// matters for picking a same-named private when $obj IS an instance of the
// scope class. zphp regressed this: code in C::method() reading
// $unrelated->help resolved to C's private string $help (wrong type +
// visibility), which falsely threw "must not be accessed before
// initialization" for an unrelated object whose own $help was a nullable
// public with a null default. this is exactly the Symfony Console shape:
// Command::__construct (private string $help) reads an AsCommand attribute's
// public ?string $help.

class Marker
{
    public ?string $help = null;
    public int $count = 7;
    protected string $label = 'marker';
}

class Engine
{
    private string $help = 'engine-help';
    private int $count = 99;
    private string $label = 'engine-label';

    public function peekHelp(object $o): ?string
    {
        return $o->help;
    }

    public function peekCount(object $o): int
    {
        return $o->count;
    }

    // reading its OWN private must still work (object IS-A Engine)
    public function ownHelp(): string
    {
        return $this->help;
    }
}

$e = new Engine();
$m = new Marker();

echo "marker.help via Engine scope: ";
var_dump($e->peekHelp($m));
echo "marker.count via Engine scope: ";
var_dump($e->peekCount($m));
echo "engine own private help: ";
var_dump($e->ownHelp());

// subclass: reading own inherited-through-hierarchy still resolves correctly
class Sub extends Engine
{
    public function go(): string
    {
        return $this->ownHelp();
    }
}
$s = new Sub();
echo "subclass own help: ";
var_dump($s->go());
