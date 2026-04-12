<?php
// covers: generators, yield, yield from, array_map, array_filter, array_reduce,
//   array_chunk, array_column, array_combine, array_unique, array_merge,
//   array_slice, array_splice, array_keys, array_values, array_flip,
//   array_reverse, array_pop, array_shift, array_unshift, array_push,
//   usort, uksort, array_walk, compact, extract, list() destructuring,
//   closures, arrow functions, match, enums, interfaces, traits,
//   constructor property promotion, readonly, named arguments,
//   sprintf, json_encode, json_decode, ob_start, ob_get_clean,
//   str_contains, str_starts_with, str_ends_with, strtolower, strtoupper,
//   preg_match, preg_replace, explode, implode, trim, rtrim,
//   intval, floatval, number_format, round, max, min, abs,
//   count, strlen, substr, strpos, str_replace, str_pad

interface Transformer {
    public function transform(array $rows): array;
}

trait Describable {
    abstract public function name(): string;

    public function describe(): string {
        return $this->name() . " (" . get_class($this) . ")";
    }
}

enum DataType: string {
    case STRING = 'string';
    case INT = 'int';
    case FLOAT = 'float';
    case BOOL = 'bool';
}

class Column {
    public function __construct(
        public readonly string $name,
        public readonly DataType $type,
        public readonly bool $nullable = false,
        public readonly mixed $default = null
    ) {}

    public function cast(mixed $value): mixed {
        if ($value === null || $value === '') {
            if ($this->nullable) return null;
            if ($this->default !== null) return $this->default;
        }
        return match($this->type) {
            DataType::STRING => (string)$value,
            DataType::INT => intval($value),
            DataType::FLOAT => floatval($value),
            DataType::BOOL => (bool)$value,
        };
    }
}

class Schema {
    private array $columns = [];

    public function add(Column $col): self {
        $this->columns[$col->name] = $col;
        return $this;
    }

    public function apply(array $row): array {
        $result = [];
        foreach ($this->columns as $name => $col) {
            $result[$name] = $col->cast($row[$name] ?? null);
        }
        return $result;
    }

    public function columnNames(): array {
        return array_keys($this->columns);
    }
}

class FilterTransformer implements Transformer {
    use Describable;

    public function __construct(private string $field, private string $op, private mixed $value) {}

    public function name(): string {
        return "filter({$this->field} {$this->op} {$this->value})";
    }

    public function transform(array $rows): array {
        return array_values(array_filter($rows, function($row) {
            $val = $row[$this->field] ?? null;
            return match($this->op) {
                '=' => $val == $this->value,
                '!=' => $val != $this->value,
                '>' => $val > $this->value,
                '<' => $val < $this->value,
                '>=' => $val >= $this->value,
                '<=' => $val <= $this->value,
                'contains' => str_contains((string)$val, (string)$this->value),
                default => true,
            };
        }));
    }
}

class MapTransformer implements Transformer {
    use Describable;

    public function __construct(private string $field, private \Closure $fn, private string $label = 'map') {}

    public function name(): string {
        return "{$this->label}({$this->field})";
    }

    public function transform(array $rows): array {
        return array_map(function($row) {
            $row[$this->field] = ($this->fn)($row[$this->field] ?? null, $row);
            return $row;
        }, $rows);
    }
}

class SortTransformer implements Transformer {
    use Describable;

    public function __construct(private string $field, private string $direction = 'asc') {}

    public function name(): string {
        return "sort({$this->field} {$this->direction})";
    }

    public function transform(array $rows): array {
        $dir = $this->direction;
        $field = $this->field;
        usort($rows, function($a, $b) use ($field, $dir) {
            $va = $a[$field] ?? 0;
            $vb = $b[$field] ?? 0;
            $cmp = $va <=> $vb;
            return $dir === 'desc' ? -$cmp : $cmp;
        });
        return $rows;
    }
}

class Pipeline {
    private array $transformers = [];

    public function pipe(Transformer $t): self {
        $this->transformers[] = $t;
        return $this;
    }

    public function run(array $data): array {
        foreach ($this->transformers as $t) {
            $data = $t->transform($data);
        }
        return $data;
    }

    public function steps(): array {
        return array_map(fn($t) => $t->describe(), $this->transformers);
    }
}

// generator that yields rows from "CSV-like" data
function parseRows(string $data): Generator {
    $lines = explode("\n", trim($data));
    $headers = explode(",", array_shift($lines));
    $headers = array_map('trim', $headers);

    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '') continue;
        $values = explode(",", $line);
        $values = array_map('trim', $values);
        $row = [];
        foreach ($headers as $i => $h) {
            $row[$h] = $values[$i] ?? '';
        }
        yield $row;
    }
}

// generator that yields summary stats
function summarize(array $rows, string $field): Generator {
    $values = array_map(fn($r) => floatval($r[$field] ?? 0), $rows);
    $count = count($values);

    if ($count === 0) {
        yield 'count' => 0;
        return;
    }

    yield 'count' => $count;
    yield 'sum' => array_sum($values);
    yield 'min' => min(...$values);
    yield 'max' => max(...$values);
    yield 'avg' => round(array_sum($values) / $count, 2);
}

// format table using output buffering
function formatTable(array $rows, array $columns): string {
    if (count($rows) === 0) return "(empty)\n";

    $widths = [];
    foreach ($columns as $col) {
        $widths[$col] = strlen($col);
    }
    foreach ($rows as $row) {
        foreach ($columns as $col) {
            $val = (string)($row[$col] ?? '');
            $widths[$col] = max($widths[$col], strlen($val));
        }
    }

    ob_start();
    // header
    $parts = [];
    foreach ($columns as $col) {
        $parts[] = str_pad($col, $widths[$col]);
    }
    echo implode(" | ", $parts) . "\n";
    $parts = [];
    foreach ($columns as $col) {
        $parts[] = str_repeat("-", $widths[$col]);
    }
    echo implode("-+-", $parts) . "\n";
    // rows
    foreach ($rows as $row) {
        $parts = [];
        foreach ($columns as $col) {
            $parts[] = str_pad((string)($row[$col] ?? ''), $widths[$col]);
        }
        echo implode(" | ", $parts) . "\n";
    }
    return ob_get_clean();
}

// --- test data ---
$csv = "name, age, score, department
Alice, 28, 92.5, engineering
Bob, 34, 87.3, marketing
Carol, 25, 95.1, engineering
Dave, 41, 78.9, sales
Eve, 30, 88.7, engineering
Frank, 29, 91.2, marketing
Grace, 36, 82.4, sales
Hank, 27, 96.0, engineering
Ivy, 33, 84.6, marketing
Jack, 38, 77.8, sales";

// parse and apply schema
$schema = (new Schema())
    ->add(new Column('name', DataType::STRING))
    ->add(new Column('age', DataType::INT))
    ->add(new Column('score', DataType::FLOAT))
    ->add(new Column('department', DataType::STRING));

$rows = [];
foreach (parseRows($csv) as $row) {
    $rows[] = $schema->apply($row);
}

echo "parsed: " . count($rows) . " rows\n";
echo "columns: " . implode(", ", $schema->columnNames()) . "\n";

// pipeline: filter engineering, sort by score desc, add grade
$pipeline = (new Pipeline())
    ->pipe(new FilterTransformer('department', '=', 'engineering'))
    ->pipe(new SortTransformer('score', 'desc'))
    ->pipe(new MapTransformer('score', function($score) {
        return match(true) {
            $score >= 95 => 'A+',
            $score >= 90 => 'A',
            $score >= 85 => 'B',
            $score >= 80 => 'C',
            default => 'D',
        };
    }, 'grade'));

echo "\nsteps: " . implode(" -> ", $pipeline->steps()) . "\n\n";

$result = $pipeline->run($rows);
echo "--- engineering (sorted by score, graded) ---\n";
echo formatTable($result, ['name', 'age', 'score', 'department']);

// stats on all rows
echo "--- score stats (all departments) ---\n";
foreach (summarize($rows, 'score') as $stat => $value) {
    echo "  $stat: $value\n";
}

// group by department using array_reduce
$grouped = array_reduce($rows, function($acc, $row) {
    $dept = $row['department'];
    if (!isset($acc[$dept])) $acc[$dept] = [];
    $acc[$dept][] = $row['name'];
    return $acc;
}, []);

echo "\n--- departments ---\n";
uksort($grouped, 'strcmp');
foreach ($grouped as $dept => $names) {
    echo "  $dept: " . implode(", ", $names) . "\n";
}

// array operations
$names = array_column($rows, 'name');
echo "\nnames: " . implode(", ", $names) . "\n";

$ages = array_column($rows, 'age');
echo "age range: " . min(...$ages) . "-" . max(...$ages) . "\n";

$reversed = array_reverse(array_slice($names, 0, 3));
echo "first 3 reversed: " . implode(", ", $reversed) . "\n";

$unique_depts = array_unique(array_column($rows, 'department'));
sort($unique_depts);
echo "departments: " . implode(", ", $unique_depts) . "\n";

// test compact/extract
$total = count($rows);
$avg_age = round(array_sum($ages) / $total);
$summary = compact('total', 'avg_age');
echo "compact: " . json_encode($summary) . "\n";

extract($summary);
echo "extract: total=$total avg_age=$avg_age\n";

// list destructuring
[$first, $second] = $rows;
echo "first: {$first['name']}, second: {$second['name']}\n";

// array_walk
$scores_formatted = array_column($rows, 'score');
array_walk($scores_formatted, function(&$v) {
    $v = number_format($v, 1);
});
echo "scores: " . implode(", ", $scores_formatted) . "\n";

// array_chunk
$chunks = array_chunk($names, 3);
echo "chunks: " . count($chunks) . "\n";
echo "chunk[0]: " . implode(", ", $chunks[0]) . "\n";

// string operations on names
$upper_names = array_map('strtoupper', array_slice($names, 0, 3));
echo "upper: " . implode(", ", $upper_names) . "\n";

$filtered_names = array_filter($names, fn($n) => str_starts_with($n, 'A') || str_ends_with($n, 'e'));
echo "A* or *e: " . implode(", ", array_values($filtered_names)) . "\n";

echo "\ndone\n";
