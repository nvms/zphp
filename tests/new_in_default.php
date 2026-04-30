<?php

class Logger {
    public function __construct(public string $name = "default") {}
    public function tag(): string { return "[" . $this->name . "]"; }
}

// new in default for plain function param
function svc(Logger $l = new Logger("svc")): string { return $l->tag(); }
echo svc() . "\n";
echo svc(new Logger("custom")) . "\n";

// new in default for promoted constructor param
class Service {
    public function __construct(public Logger $log = new Logger("service")) {}
}
echo (new Service())->log->tag() . "\n";
echo (new Service(new Logger("override")))->log->tag() . "\n";

// new in default - fresh instance per call
class Counter {
    public int $n = 0;
    public function inc(): int { return ++$this->n; }
}
function bump(Counter $c = new Counter()): int { return $c->inc(); }
echo bump() . "\n";
echo bump() . "\n";

// constant arg in new default
class Box {
    public function __construct(public int $size) {}
}
const DEFAULT_SIZE = 42;
function box(Box $b = new Box(DEFAULT_SIZE)): int { return $b->size; }
echo box() . "\n";

// nested new in default args
class Wrapper {
    public function __construct(public Logger $inner) {}
    public function tag(): string { return "wrap" . $this->inner->tag(); }
}
function wrap(Wrapper $w = new Wrapper(new Logger("nested"))): string { return $w->tag(); }
echo wrap() . "\n";

// method param defaults
class Repo {
    public function find(Logger $l = new Logger("repo")): string { return $l->tag(); }
}
echo (new Repo())->find() . "\n";
