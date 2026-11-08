<?php
// php's property guards: a property magic method isn't entered again for the
// same object and property while it runs, so the access inside it reaches the
// property itself, with the warnings and errors that access has

#[AllowDynamicProperties]
class Guarded
{
    public $declared;
    protected $hidden;
    private $secret;

    public function __construct()
    {
        unset($this->declared, $this->hidden, $this->secret);
    }

    public function __get($name)
    {
        echo "__get $name\n";
        return $this->$name;
    }

    public function __set($name, $value)
    {
        echo "__set $name\n";
        $this->$name = $value;
    }

    public function __isset($name)
    {
        echo "__isset $name\n";
        return isset($this->$name);
    }

    public function __unset($name)
    {
        echo "__unset $name\n";
        unset($this->$name);
    }
}

$g = new Guarded();
var_dump($g->missing);
var_dump($g->declared);
var_dump($g->hidden);
var_dump(isset($g->missing), isset($g->declared), isset($g->secret));
$g->missing = 1;
$g->declared = 2;
$g->hidden = 3;
var_dump($g->missing, $g->declared, $g->hidden);
unset($g->missing);
unset($g->declared);
var_dump(isset($g->missing), isset($g->declared));

// the guard is per property: another name inside the method calls it again
class Forward
{
    public function __get($name)
    {
        echo "get $name\n";
        if (strlen($name) < 3) {
            return $this->{$name . "+"};
        }
        return $name;
    }
}
var_dump((new Forward())->a);

// and per object: the same name on another object calls it again
class Pair
{
    public ?Pair $other = null;

    public function __get($name)
    {
        echo "pair get $name\n";
        return $this->other ? $this->other->$name : "end";
    }
}
$p = new Pair();
$p->other = new Pair();
var_dump($p->x);

// __unset unsetting the property it was called for
class Unsetter
{
    public function __unset($prop)
    {
        echo "unset $prop\n";
        unset($this->$prop);
    }
}
$u = new Unsetter();
unset($u->gone);
echo "unset done\n";

// a name starting with a nul byte can't be a property
try {
    unset($u->{"\0x"});
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
// a private(set) property unset by its own __unset, which runs once and
// then meets the asymmetric visibility rule
class Asym
{
    public private(set) int $a = 1;

    public function __construct()
    {
        unset($this->a);
    }
}
class AsymChild extends Asym
{
    public function __unset($name)
    {
        echo "AsymChild::__unset $name\n";
        unset($this->a);
    }
}
$c = new AsymChild();
try {
    unset($c->a);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump($c);

// an inaccessible property with a guarded __get is an access error
class Private_
{
    private $p = 1;

    public function __get($name)
    {
        global $outside;
        return $outside->$name;
    }
}
$outside = new Private_();
function readPrivate($o)
{
    try {
        var_dump($o->p);
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
readPrivate($outside);

// (closures are objects in php: kept last so the handles above agree)
class NoMagic
{
}
$n = new NoMagic();
foreach (['read' => fn() => $n->{"\0y"}, 'write' => function () use ($n) { $n->{"\0y"} = 1; }, 'unset' => function () use ($n) { unset($n->{"\0y"}); }] as $what => $fn) {
    try {
        $fn();
        echo "$what: no error\n";
    } catch (Error $e) {
        echo "$what: ", $e->getMessage(), "\n";
    }
}

// `??` asks __isset first, then __get; each is skipped while it runs for the
// property, and only a running __get makes an inaccessible property an error
class Coalesce
{
    private $p = 1;
    public $log = [];

    public function __isset($name)
    {
        $this->log[] = "isset $name";
        return ($this->$name ?? "unset") !== "skip";
    }

    public function __get($name)
    {
        $this->log[] = "get $name";
        return $this->$name ?? "fallback";
    }
}
$c = new Coalesce();
var_dump($c->p ?? "none", $c->q ?? "none");
echo implode(", ", $c->log), "\n";

class GetOnly
{
    private $p = 1;

    public function __get($name)
    {
        try {
            return $this->other->$name ?? "default";
        } catch (Error $e) {
            return $e->getMessage();
        }
    }

    public ?GetOnly $other = null;
}
$a = new GetOnly();
$a->other = $a;
var_dump($a->p ?? "none", $a->q ?? "none");
