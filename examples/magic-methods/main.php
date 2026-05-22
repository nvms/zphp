<?php
// covers: __get / __set / __isset / __unset (property overloading), __call
//   and __callStatic (method overloading), __invoke (callable objects),
//   __toString (string conversion), and how they interact with isset(),
//   unset(), string interpolation, is_callable() and array_map()

class Record
{
    private array $data = [];

    // a named-constructor pattern via __callStatic: Record::of([...])
    public static function __callStatic(string $name, array $args): static
    {
        $r = new static();
        if ($name === 'of') {
            foreach ($args[0] ?? [] as $k => $v) {
                $r->$k = $v;
            }
        }
        return $r;
    }

    public function __get(string $key): mixed
    {
        return $this->data[$key] ?? null;
    }

    public function __set(string $key, mixed $value): void
    {
        $this->data[$key] = $value;
    }

    public function __isset(string $key): bool
    {
        return isset($this->data[$key]);
    }

    public function __unset(string $key): void
    {
        unset($this->data[$key]);
    }

    public function __toString(): string
    {
        $parts = [];
        foreach ($this->data as $k => $v) {
            $parts[] = "{$k}={$v}";
        }
        return '{' . implode(', ', $parts) . '}';
    }
}

class Query
{
    private array $clauses = [];

    // every unknown method becomes a fluent clause
    public function __call(string $name, array $args): static
    {
        $this->clauses[] = $name . '(' . implode(', ', $args) . ')';
        return $this;
    }

    public function __toString(): string
    {
        return implode(' -> ', $this->clauses);
    }
}

class Discount
{
    public function __construct(private float $rate)
    {
    }

    public function __invoke(float $price): float
    {
        return round($price * (1 - $this->rate), 2);
    }
}

echo "== property overloading ==\n";
$user = Record::of(['name' => 'Ada', 'role' => 'admin']);
$user->active = true;
echo 'name: ', $user->name, "\n";
echo 'missing: ', var_export($user->missing, true), "\n";
echo 'isset role: ', isset($user->role) ? 'yes' : 'no', "\n";
echo 'isset missing: ', isset($user->missing) ? 'yes' : 'no', "\n";
unset($user->role);
echo 'isset role after unset: ', isset($user->role) ? 'yes' : 'no', "\n";
echo "record: {$user}\n";

echo "== method overloading ==\n";
$q = (new Query())->where('age > 18')->orderBy('name')->limit(10);
echo 'query: ', $q, "\n";
echo 'static factory: ', Record::of(['k' => 'v']), "\n";

echo "== callable objects ==\n";
$halfOff = new Discount(0.5);
echo 'is_callable: ', is_callable($halfOff) ? 'yes' : 'no', "\n";
echo 'direct: ', $halfOff(80.0), "\n";
echo 'via array_map: ', implode(', ', array_map($halfOff, [100.0, 50.0, 30.0])), "\n";

echo "done\n";
