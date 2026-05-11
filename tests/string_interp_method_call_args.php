<?php
class M {
    public string $name = "default";
    public function s(string $x): string { return "got: $x"; }
    public function multi(string $a, int $b, bool $c): string {
        return "$a/$b/" . ($c ? "y" : "n");
    }
}

$m = new M;
echo "dq: {$m->s('hi')}\n";

echo <<<EOT
hd: {$m->s('hi')}
EOT, "\n";

echo <<<EOT
hd2: {$m->multi("x", 42, true)}
EOT, "\n";

echo "multi: {$m->multi('a', 7, false)}\n";

$name = "var";
echo "withvar: {$m->s($name)}\n";

echo "result: {$m->name} and {$m->s($name)}\n";

class Holder {
    private array $data = ["x", "y", "z"];
    public function get(int $i): string { return $this->data[$i]; }
}
$h = new Holder;
echo "idx: {$h->get(0)} {$h->get(1)} {$h->get(2)}\n";

class Chain {
    public function __construct(public string $val = "init") {}
    public function withSuffix(string $s): string {
        return "{$this->val}-{$s}";
    }
}
$c = new Chain("base");
echo "{$c->withSuffix('end')}\n";

echo <<<EOT
{$c->withSuffix("finish")}
EOT, "\n";
