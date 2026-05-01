<?php

// multiple instances of the same anonymous class definition each get their
// own property storage (regression test - earlier the second instantiation
// freed the first's slot_layout)
function maker(int $val) {
    return new class($val) {
        public function __construct(public int $n) {}
        public function show(): string { return "n=$this->n"; }
    };
}

$a = maker(1);
$b = maker(2);
$c = maker(3);
echo $a->show() . "\n";
echo $b->show() . "\n";
echo $c->show() . "\n";

// recursive anon-class chain (PSR-15-style middleware)
interface H { public function h(array $r): array; }
interface M { public function p(array $r, H $h): array; }

class FinalHandler implements H { public function h(array $r): array { return ['final']; } }
class StepMw implements M {
    public function __construct(private string $name) {}
    public function p(array $r, H $h): array { return [$this->name, ...$h->h($r)]; }
}

class Pipe implements H {
    private array $mws = [];
    public function __construct(private H $final) {}
    public function add(M $m): static { $this->mws[] = $m; return $this; }
    public function h(array $r): array { return $this->build(0)->h($r); }

    private function build(int $i): H {
        if ($i >= count($this->mws)) return $this->final;
        $next = $this->build($i + 1);
        $mw = $this->mws[$i];
        return new class($mw, $next) implements H {
            public function __construct(private M $mw, private H $next) {}
            public function h(array $r): array { return $this->mw->p($r, $this->next); }
        };
    }
}

$pipe = (new Pipe(new FinalHandler()))
    ->add(new StepMw('a'))
    ->add(new StepMw('b'))
    ->add(new StepMw('c'));

print_r($pipe->h([]));

// nested anon classes share state correctly with $this
$counter = new class {
    public int $n = 0;
    public function inc(): void { $this->n++; }
};
$counter->inc();
$counter->inc();
$counter->inc();
echo $counter->n . "\n";

// anon class in a loop creates separate instances
$items = [];
foreach ([10, 20, 30] as $v) {
    $items[] = new class($v) {
        public function __construct(public int $value) {}
    };
}
echo $items[0]->value . "/" . $items[1]->value . "/" . $items[2]->value . "\n";
