<?php
$a = new class {
    public string $name = "anon";
    public function greet(): string { return "hello from " . $this->name; }
};
echo $a->greet(), "\n";
echo $a->name, "\n";
echo str_starts_with(get_class($a), "class@anonymous") ? "y" : "n", "\n";

$b = new class("alice", 30) {
    public function __construct(public string $name, public int $age) {}
};
echo $b->name, " ", $b->age, "\n";

$g = new class(...["start" => 10]) {
    public function __construct(public int $start) {}
};
echo $g->start, "\n";

interface Speaker { public function speak(): string; }
$c = new class implements Speaker {
    public function speak(): string { return "I speak"; }
};
echo $c->speak(), "\n";
echo $c instanceof Speaker ? "y" : "n", "\n";

class Base {
    public string $title = "base";
    public function describe(): string { return "I am " . $this->title; }
}
$d = new class extends Base {
    public string $title = "anon-child";
    public function describe(): string { return parent::describe() . " (overridden)"; }
};
echo $d->describe(), "\n";
echo $d instanceof Base ? "y" : "n", "\n";

trait Hello { public function hi(): string { return "Hi from trait"; } }
$e = new class { use Hello; };
echo $e->hi(), "\n";

$outer = "captured value";
$f = new class($outer) {
    public function __construct(public string $val) {}
    public function show(): string { return "got: $this->val"; }
};
echo $f->show(), "\n";

abstract class AbstractBase {
    abstract public function go(): string;
    public function callGo(): string { return $this->go() . "!"; }
}
$i = new class extends AbstractBase {
    public function go(): string { return "I go"; }
};
echo $i->callGo(), "\n";
echo $i instanceof AbstractBase ? "y" : "n", "\n";

$rc = new ReflectionClass($i);
echo $rc->isAnonymous() ? "y" : "n", "\n";

function makeAnon(int $x) {
    return new class($x) {
        public function __construct(public int $val) {}
        public function double(): int { return $this->val * 2; }
    };
}
echo makeAnon(21)->double(), "\n";

$instances = [];
for ($i = 0; $i < 3; $i++) {
    $instances[] = new class($i) {
        public function __construct(public int $n) {}
    };
}
foreach ($instances as $inst) echo $inst->n, " ";
echo "\n";
echo get_class($instances[0]) === get_class($instances[1]) ? "same\n" : "diff\n";
