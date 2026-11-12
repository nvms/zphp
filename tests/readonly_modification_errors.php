<?php
// an initialized readonly property is refused as readonly before its
// implicit protected(set) is considered
class Test {
    public function __construct(public readonly int $prop = 1, public readonly array $list = []) {}
    public function initLater(): void {}
}
$t = new Test();
foreach ([
    'write' => fn() => $t->prop = 2,
    'unset' => function () use ($t) { unset($t->prop); },
    'append' => fn() => $t->list[] = 1,
    'dim' => fn() => $t->list['k'] = 1,
    'unset dim' => function () use ($t) { unset($t->list['k']); },
] as $what => $f) {
    try {
        $f();
        echo "$what: done\n";
    } catch (Error $e) {
        echo "$what: ", $e->getMessage(), "\n";
    }
}
class Lazy {
    public readonly array $items;
}
$l = new Lazy();
try { $l->items[] = 1; } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { unset($l->items['x']); echo "unset of nothing\n"; } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $l->items = [1]; } catch (Error $e) { echo $e->getMessage(), "\n"; }
