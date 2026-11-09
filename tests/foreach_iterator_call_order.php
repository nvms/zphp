<?php
// foreach over an Iterator asks for current() before key(), and for key()
// only when the loop has a key variable

class Logged implements Iterator
{
    private int $i = 0;

    public function __construct(private array $items) {}
    public function rewind(): void { echo "rewind\n"; $this->i = 0; }
    public function valid(): bool { echo "valid\n"; return $this->i < count($this->items); }
    public function current(): mixed { echo "current\n"; return $this->items[$this->i]; }
    public function key(): mixed { echo "key\n"; return "k{$this->i}"; }
    public function next(): void { echo "next\n"; $this->i++; }
}

foreach (new Logged(['a', 'b']) as $value) {
    echo "value $value\n";
}
foreach (new Logged(['a', 'b']) as $key => $value) {
    echo "pair $key $value\n";
}
foreach (new Logged([[1, 2]]) as [$x, $y]) {
    echo "list $x $y\n";
}
foreach (new Logged([[1, 2]]) as $key => [$x, $y]) {
    echo "keyed list $key $x $y\n";
}

class KeyFails extends Logged
{
    public function key(): mixed
    {
        throw new RuntimeException('no keys here');
    }
}
foreach (new KeyFails(['only values']) as $value) {
    echo "value $value\n";
}
try {
    foreach (new KeyFails(['x']) as $key => $value) {
        echo "never\n";
    }
} catch (RuntimeException $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

function gen()
{
    yield 'a' => 1;
    yield 'b' => 2;
}
foreach (gen() as $v) {
    echo "gen $v\n";
}
foreach (gen() as $k => $v) {
    echo "gen $k $v\n";
}
