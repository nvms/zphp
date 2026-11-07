<?php
// an exception from an Iterator's rewind() or next() leaves foreach and
// array spreading as it does from valid(), key() and current()

class It implements Iterator {
    private $i = 0;
    public function __construct(private string $fail) {}
    private function step(string $m) {
        // key() and current() stay quiet: php and zphp call them in different orders
        if ($m !== 'key' && $m !== 'current') echo "$m\n";
        if ($m === $this->fail) throw new RuntimeException("$m failed");
    }
    public function rewind(): void { $this->step('rewind'); $this->i = 0; }
    public function valid(): bool { $this->step('valid'); return $this->i < 2; }
    public function key(): mixed { $this->step('key'); return $this->i; }
    public function current(): mixed { $this->step('current'); return $this->i * 10; }
    public function next(): void { $this->step('next'); $this->i++; }
}

foreach (['rewind', 'valid', 'key', 'current', 'next'] as $fail) {
    echo "== foreach, $fail throws\n";
    try {
        foreach (new It($fail) as $k => $v) {
            echo "$k => $v\n";
        }
        echo "loop finished\n";
    } catch (RuntimeException $e) {
        echo "caught: ", $e->getMessage(), "\n";
    }
}

foreach (['rewind', 'valid', 'key', 'current', 'next'] as $fail) {
    echo "== spread, $fail throws\n";
    try {
        $a = [...new It($fail)];
        var_dump($a);
    } catch (RuntimeException $e) {
        echo "caught: ", $e->getMessage(), "\n";
    }
}

function inFunction() {
    $total = 0;
    foreach ([1, 2] as $outer) {
        try {
            foreach (new It('next') as $v) {
                $total += $v;
            }
        } catch (RuntimeException $e) {
            echo "inner caught: ", $e->getMessage(), "\n";
        }
    }
    return $total;
}
var_dump(inFunction());

echo "== uncaught\n";
foreach (new It('next') as $v) echo "$v\n";
echo "not reached\n";
