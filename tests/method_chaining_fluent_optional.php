<?php
class Builder {
    private array $parts = [];
    public function add(string $p): self { $this->parts[] = $p; return $this; }
    public function build(): string { return implode("-", $this->parts); }
}

echo (new Builder)->add("a")->add("b")->add("c")->build(), "\n";

$b = new Builder;
$result = $b->add("x")->add("y")->add("z")->build();
echo $result, "\n";

class Query {
    private array $where = [];
    private array $select = ["*"];
    private string $table = "";
    private ?int $limit = null;
    public function from(string $t): self { $this->table = $t; return $this; }
    public function select(string ...$cols): self { $this->select = $cols; return $this; }
    public function where(string $c): self { $this->where[] = $c; return $this; }
    public function limit(int $n): self { $this->limit = $n; return $this; }
    public function sql(): string {
        $sql = "SELECT " . implode(",", $this->select) . " FROM " . $this->table;
        if (!empty($this->where)) $sql .= " WHERE " . implode(" AND ", $this->where);
        if ($this->limit !== null) $sql .= " LIMIT " . $this->limit;
        return $sql;
    }
}

echo (new Query)
    ->from("users")
    ->select("id", "name")
    ->where("active=1")
    ->where("age>18")
    ->limit(10)
    ->sql(), "\n";

class Tree {
    public ?Tree $left = null;
    public ?Tree $right = null;
    public function __construct(public int $val) {}
    public function setLeft(self $t): self { $this->left = $t; return $this; }
    public function setRight(self $t): self { $this->right = $t; return $this; }
}

$t = (new Tree(1))
    ->setLeft((new Tree(2))->setLeft(new Tree(4)))
    ->setRight(new Tree(3));

echo $t->val, "\n";
echo $t->left->val, "\n";
echo $t->left->left->val, "\n";
echo $t->right->val, "\n";

class Optional {
    public function __construct(private ?string $value) {}
    public function map(callable $fn): self {
        return new self($this->value === null ? null : $fn($this->value));
    }
    public function get(): ?string { return $this->value; }
}

$result = (new Optional("hello"))
    ->map(fn($s) => strtoupper($s))
    ->map(fn($s) => $s . "!")
    ->get();
echo $result, "\n";

$nullResult = (new Optional(null))
    ->map(fn($s) => strtoupper($s))
    ->map(fn($s) => $s . "!")
    ->get();
echo var_export($nullResult, true), "\n";

class Person {
    public ?Address $address = null;
    public function setAddress(?Address $a): self { $this->address = $a; return $this; }
}
class Address {
    public ?string $city = null;
    public function setCity(string $c): self { $this->city = $c; return $this; }
}

$p = (new Person)->setAddress((new Address)->setCity("Springfield"));
echo $p->address->city, "\n";
echo $p?->address?->city, "\n";

$p2 = new Person;
echo $p2?->address?->city ?? "null", "\n";

class List_ {
    private array $items = [];
    public function add($x): self { $this->items[] = $x; return $this; }
    public function map(callable $f): self {
        $new = new self;
        foreach ($this->items as $i) $new->add($f($i));
        return $new;
    }
    public function filter(callable $f): self {
        $new = new self;
        foreach ($this->items as $i) if ($f($i)) $new->add($i);
        return $new;
    }
    public function reduce(callable $f, $init) {
        $acc = $init;
        foreach ($this->items as $i) $acc = $f($acc, $i);
        return $acc;
    }
    public function toArray(): array { return $this->items; }
}

$sum = (new List_)
    ->add(1)->add(2)->add(3)->add(4)->add(5)
    ->filter(fn($x) => $x % 2 === 0)
    ->map(fn($x) => $x * 10)
    ->reduce(fn($a, $b) => $a + $b, 0);
echo $sum, "\n";

class Calculator {
    public function __construct(public float $val = 0.0) {}
    public function add(float $x): self { $this->val += $x; return $this; }
    public function sub(float $x): self { $this->val -= $x; return $this; }
    public function mul(float $x): self { $this->val *= $x; return $this; }
    public function div(float $x): self {
        if ($x === 0.0) throw new \RuntimeException("div by zero");
        $this->val /= $x;
        return $this;
    }
}

$c = (new Calculator(10))->add(5)->mul(2)->sub(3)->div(2);
echo $c->val, "\n";

$cFresh = new Calculator(100);
$cFresh->add(50)->mul(2);
echo $cFresh->val, "\n";

class Chain {
    public array $data = [];
    public function push($v): self { $this->data[] = $v; return $this; }
    public function pop(): self { array_pop($this->data); return $this; }
    public function reverse(): self { $this->data = array_reverse($this->data); return $this; }
}

$ch = (new Chain)->push(1)->push(2)->push(3)->push(4)->pop()->reverse();
print_r($ch->data);

class Box {
    public function __construct(public mixed $val = null) {}
    public function set($v): self { $this->val = $v; return $this; }
    public function get(): mixed { return $this->val; }
}

$nested = (new Box)
    ->set((new Box)->set("inner")->get())
    ->get();
echo $nested, "\n";

class Maybe {
    private mixed $value;
    public function __construct(mixed $v) { $this->value = $v; }
    public function transform(callable $f): self {
        return new self($this->value === null ? null : $f($this->value));
    }
    public function or(mixed $d): mixed {
        return $this->value ?? $d;
    }
}

echo (new Maybe(5))->transform(fn($x) => $x * 2)->or(0), "\n";
echo (new Maybe(null))->transform(fn($x) => $x * 2)->or(99), "\n";

class StaticChain {
    public static function create(): self { return new self; }
    public function step1(): self { return $this; }
    public function step2(): self { return $this; }
    public function result(): string { return "done"; }
}

echo StaticChain::create()->step1()->step2()->result(), "\n";

class Pipeline {
    private array $steps = [];
    public function pipe(callable $f): self {
        $this->steps[] = $f;
        return $this;
    }
    public function run($x) {
        foreach ($this->steps as $f) $x = $f($x);
        return $x;
    }
}

$p = (new Pipeline)
    ->pipe(fn($x) => $x + 1)
    ->pipe(fn($x) => $x * 2)
    ->pipe(fn($x) => $x - 3);
echo $p->run(5), "\n";
echo $p->run(10), "\n";
