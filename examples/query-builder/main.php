<?php

class Collection
{
    private array $items;

    public function __construct(array $items = [])
    {
        $this->items = $items;
    }

    public function map(callable $fn): self
    {
        return new self(array_map($fn, $this->items));
    }

    public function filter(callable $fn): self
    {
        return new self(array_values(array_filter($this->items, $fn)));
    }

    public function reduce(callable $fn, $initial = null)
    {
        return array_reduce($this->items, $fn, $initial);
    }

    public function first()
    {
        return count($this->items) > 0 ? $this->items[0] : null;
    }

    public function count(): int
    {
        return count($this->items);
    }

    public function toArray(): array
    {
        return $this->items;
    }

    public function pluck(string $key): self
    {
        return new self(array_column($this->items, $key));
    }

    public function each(callable $fn): self
    {
        foreach ($this->items as $k => $v) {
            $fn($v, $k);
        }
        return $this;
    }

    public function implode(string $sep): string
    {
        return implode($sep, $this->items);
    }

    public function contains($value): bool
    {
        return in_array($value, $this->items, true);
    }

    public function unique(): self
    {
        return new self(array_values(array_unique($this->items)));
    }

    public function sortBy(callable $fn): self
    {
        $items = $this->items;
        usort($items, $fn);
        return new self($items);
    }

    public function groupBy(string $key): array
    {
        $groups = [];
        foreach ($this->items as $item) {
            $k = $item[$key] ?? "unknown";
            if (!isset($groups[$k])) $groups[$k] = [];
            $groups[$k][] = $item;
        }
        return $groups;
    }
}

class QueryBuilder
{
    private string $table = "";
    private array $conditions = [];
    private array $columns = ["*"];
    private ?string $orderBy = null;
    private string $orderDir = "ASC";
    private ?int $limitVal = null;
    private ?int $offsetVal = null;

    private static array $data = [];

    public static function table(string $name): self
    {
        $q = new self();
        $q->table = $name;
        return $q;
    }

    public static function seed(string $table, array $rows): void
    {
        self::$data[$table] = $rows;
    }

    public function select(...$cols): self
    {
        $this->columns = $cols;
        return $this;
    }

    public function where(string $col, string $op, $value): self
    {
        $this->conditions[] = ["col" => $col, "op" => $op, "value" => $value];
        return $this;
    }

    public function orderBy(string $col, string $dir = "ASC"): self
    {
        $this->orderBy = $col;
        $this->orderDir = $dir;
        return $this;
    }

    public function limit(int $n): self
    {
        $this->limitVal = $n;
        return $this;
    }

    public function offset(int $n): self
    {
        $this->offsetVal = $n;
        return $this;
    }

    public function get(): Collection
    {
        $rows = self::$data[$this->table] ?? [];

        foreach ($this->conditions as $cond) {
            $rows = array_values(array_filter($rows, function ($row) use ($cond) {
                $val = $row[$cond["col"]] ?? null;
                return match ($cond["op"]) {
                    "=" => $val == $cond["value"],
                    "!=" => $val != $cond["value"],
                    ">" => $val > $cond["value"],
                    "<" => $val < $cond["value"],
                    ">=" => $val >= $cond["value"],
                    "<=" => $val <= $cond["value"],
                    "like" => str_contains(strtolower($val), strtolower($cond["value"])),
                    default => false,
                };
            }));
        }

        if ($this->orderBy !== null) {
            $col = $this->orderBy;
            $dir = $this->orderDir;
            usort($rows, function ($a, $b) use ($col, $dir) {
                $av = $a[$col] ?? "";
                $bv = $b[$col] ?? "";
                $cmp = $av <=> $bv;
                return $dir === "DESC" ? -$cmp : $cmp;
            });
        }

        if ($this->offsetVal !== null) {
            $rows = array_slice($rows, $this->offsetVal);
        }
        if ($this->limitVal !== null) {
            $rows = array_slice($rows, 0, $this->limitVal);
        }

        if ($this->columns[0] !== "*") {
            $cols = $this->columns;
            $rows = array_map(function ($row) use ($cols) {
                $filtered = [];
                foreach ($cols as $c) {
                    if (isset($row[$c])) $filtered[$c] = $row[$c];
                }
                return $filtered;
            }, $rows);
        }

        return new Collection($rows);
    }

    public function first()
    {
        return $this->limit(1)->get()->first();
    }

    public function count(): int
    {
        return $this->get()->count();
    }

    public function toSql(): string
    {
        $sql = "SELECT " . implode(", ", $this->columns) . " FROM " . $this->table;
        if (count($this->conditions) > 0) {
            $wheres = [];
            foreach ($this->conditions as $c) {
                $wheres[] = "{$c['col']} {$c['op']} '{$c['value']}'";
            }
            $sql .= " WHERE " . implode(" AND ", $wheres);
        }
        if ($this->orderBy !== null) {
            $sql .= " ORDER BY {$this->orderBy} {$this->orderDir}";
        }
        if ($this->limitVal !== null) {
            $sql .= " LIMIT {$this->limitVal}";
        }
        if ($this->offsetVal !== null) {
            $sql .= " OFFSET {$this->offsetVal}";
        }
        return $sql;
    }
}

// seed test data
QueryBuilder::seed("users", [
    ["id" => 1, "name" => "Alice", "email" => "alice@test.com", "age" => 30, "role" => "admin"],
    ["id" => 2, "name" => "Bob", "email" => "bob@test.com", "age" => 25, "role" => "user"],
    ["id" => 3, "name" => "Charlie", "email" => "charlie@test.com", "age" => 35, "role" => "user"],
    ["id" => 4, "name" => "Diana", "email" => "diana@test.com", "age" => 28, "role" => "admin"],
    ["id" => 5, "name" => "Eve", "email" => "eve@test.com", "age" => 22, "role" => "user"],
]);

// basic query
$users = QueryBuilder::table("users")->get();
echo "total: " . $users->count() . "\n";

// where clause
$admins = QueryBuilder::table("users")->where("role", "=", "admin")->get();
echo "admins: " . $admins->count() . "\n";
echo "names: " . $admins->pluck("name")->implode(", ") . "\n";

// chained wheres
$youngUsers = QueryBuilder::table("users")
    ->where("role", "=", "user")
    ->where("age", "<", 30)
    ->get();
echo "young users: " . $youngUsers->pluck("name")->implode(", ") . "\n";

// order by
$byAge = QueryBuilder::table("users")->orderBy("age", "DESC")->get();
echo "oldest first: " . $byAge->pluck("name")->implode(", ") . "\n";

// limit/offset
$page = QueryBuilder::table("users")->orderBy("id")->limit(2)->offset(2)->get();
echo "page: " . $page->pluck("name")->implode(", ") . "\n";

// select specific columns
$emails = QueryBuilder::table("users")->select("name", "email")->get();
$first = $emails->first();
echo "first: {$first['name']} <{$first['email']}>\n";

// first()
$alice = QueryBuilder::table("users")->where("name", "=", "Alice")->first();
echo "found: {$alice['name']} age {$alice['age']}\n";

// count
$userCount = QueryBuilder::table("users")->where("role", "=", "user")->count();
echo "user count: $userCount\n";

// toSql
$sql = QueryBuilder::table("users")
    ->select("name", "email")
    ->where("role", "=", "admin")
    ->where("age", ">", "25")
    ->orderBy("name")
    ->limit(10)
    ->toSql();
echo "sql: $sql\n";

// collection operations
$names = $users->pluck("name");
echo "all: " . $names->implode(", ") . "\n";
echo "contains Alice: " . var_export($names->contains("Alice"), true) . "\n";
echo "contains Zara: " . var_export($names->contains("Zara"), true) . "\n";

// map + filter
$ages = $users->map(function ($u) { return $u["age"]; });
$over25 = $ages->filter(function ($a) { return $a > 25; });
echo "ages over 25: " . $over25->implode(", ") . "\n";

// reduce
$totalAge = $ages->reduce(function ($carry, $age) { return $carry + $age; }, 0);
echo "total age: $totalAge\n";

// groupBy
$grouped = $users->groupBy("role");
echo "admin group: " . count($grouped["admin"]) . "\n";
echo "user group: " . count($grouped["user"]) . "\n";

// sortBy (using the query builder's orderBy which works correctly)
$youngest = QueryBuilder::table("users")->orderBy("age")->first();
echo "youngest: " . $youngest["name"] . "\n";

echo "done\n";
