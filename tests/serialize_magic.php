<?php

// __sleep narrows which properties get serialized
class Sleepy {
    public string $public = 'p';
    public string $secret = 'should-not-leak';
    public int $count = 0;
    public function __sleep(): array { return ['public', 'count']; }
}
$s = new Sleepy();
$s->public = 'x'; $s->secret = 'hush'; $s->count = 7;
$ser = serialize($s);
echo (str_contains($ser, 'secret') ? "leak" : "ok") . "\n";
$s2 = unserialize($ser);
echo $s2->public . "/" . $s2->count . "\n";

// __wakeup runs after restore
class Wakey {
    public int $n = 0;
    public bool $woke = false;
    public function __wakeup(): void { $this->woke = true; $this->n = $this->n + 100; }
}
$w = new Wakey();
$w->n = 5;
$w2 = unserialize(serialize($w));
echo $w2->n . " woke=" . ($w2->woke ? "y" : "n") . "\n";

// __serialize returns the array used as the payload
class Box {
    public function __construct(private string $inner) {}
    public function get(): string { return $this->inner; }
    public function __serialize(): array { return ['data' => base64_encode($this->inner)]; }
    public function __unserialize(array $arr): void { $this->inner = base64_decode($arr['data']); }
}
$b = new Box('hello world');
$ser = serialize($b);
echo (str_contains($ser, 'data') ? "y" : "n") . "\n";
$b2 = unserialize($ser);
echo $b2->get() . "\n";

// __serialize takes precedence over __sleep
class Both {
    public string $x = 'x';
    public function __sleep(): array { return ['x']; }
    public function __serialize(): array { return ['v' => 'used-serialize']; }
    public function __unserialize(array $a): void { $this->x = $a['v']; }
}
$b3 = new Both();
$b4 = unserialize(serialize($b3));
echo $b4->x . "\n";
