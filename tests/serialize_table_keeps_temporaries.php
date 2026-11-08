<?php
// serialize() keeps each object it has written alive until it finishes, so
// a temporary written inside Serializable::serialize() and then freed can't
// be mistaken for the next one at the same address
class Point { public function __construct(public int $n) {} public function __destruct() { echo "free {$this->n}\n"; } }
class Wrapper implements Serializable {
    public function __construct(public Point $p) {}
    public function serialize(): string { return serialize(clone $this->p); }
    public function unserialize(string $data): void { $this->p = unserialize($data); }
}
$out = serialize([new Wrapper(new Point(1)), new Wrapper(new Point(2))]);
echo $out, "\n";
$back = unserialize($out);
echo $back[0]->p->n, ' ', $back[1]->p->n, "\n";
echo serialize(new Point(3)), "\n";
echo "end\n";
