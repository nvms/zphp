<?php
// covers: serialize/unserialize (scalars, arrays, nested arrays, objects,
//   private/protected properties, class hierarchy), json_encode/json_decode,
//   INF/NAN edge cases, array_map, implode, is_nan,
//   is_infinite, gettype, class properties, inheritance, type coercion

// --- scalar roundtrips ---

$scalars = [null, true, false, 0, 1, -42, 3.14, -0.0, '', 'hello', "with\nnewline"];

echo "=== Scalar Roundtrips ===\n";
foreach ($scalars as $val) {
    $ser = serialize($val);
    $back = unserialize($ser);
    $match = ($val === $back) ? 'ok' : 'FAIL';
    echo gettype($val) . ': ' . $match . "\n";
}

// --- special float values ---

echo "\n=== Special Float Values ===\n";
$inf = INF;
$ninf = -INF;
$nan = NAN;

echo 'INF serialize: ' . serialize($inf) . "\n";
echo 'INF unserialize match: ' . (unserialize(serialize($inf)) === INF ? 'ok' : 'FAIL') . "\n";
echo '-INF serialize: ' . serialize($ninf) . "\n";
echo '-INF unserialize match: ' . (unserialize(serialize($ninf)) === -INF ? 'ok' : 'FAIL') . "\n";
echo 'NAN serialize: ' . serialize($nan) . "\n";
echo 'NAN unserialize is_nan: ' . (is_nan(unserialize(serialize($nan))) ? 'ok' : 'FAIL') . "\n";

// --- array roundtrips ---

echo "\n=== Array Roundtrips ===\n";

$arrays = [
    'empty' => [],
    'indexed' => [1, 2, 3],
    'assoc' => ['a' => 1, 'b' => 2],
    'nested' => ['x' => [1, [2, 3]], 'y' => ['z' => 'deep']],
    'mixed_keys' => [0 => 'zero', 'one' => 1, 2 => 'two'],
    'sparse' => [0 => 'a', 5 => 'b', 10 => 'c'],
];

foreach ($arrays as $name => $arr) {
    $back = unserialize(serialize($arr));
    echo $name . ': ' . ($arr === $back ? 'ok' : 'FAIL') . "\n";
}

// --- serialize format details ---

echo "\n=== Serialize Format ===\n";

echo "null: " . serialize(null) . "\n";
echo "true: " . serialize(true) . "\n";
echo "false: " . serialize(false) . "\n";
echo "int 42: " . serialize(42) . "\n";
echo "float 2.5: " . serialize(2.5) . "\n";
echo "string abc: " . serialize('abc') . "\n";
echo "empty array: " . serialize([]) . "\n";
echo "array [1,2]: " . serialize([1, 2]) . "\n";

// --- unserialize malformed input ---

echo "\n=== Malformed Input ===\n";

$bad_inputs = ['', 'garbage', 'i:abc;', 's:99:"short";'];
foreach ($bad_inputs as $input) {
    $result = @unserialize($input);
    echo "'" . $input . "': " . ($result === false ? 'false' : gettype($result)) . "\n";
}

// --- type coercion in serialization ---

echo "\n=== Type Preservation ===\n";

$mixed = [
    'int' => 42,
    'float' => 42.0,
    'string_num' => '42',
    'bool_true' => true,
];

$back = unserialize(serialize($mixed));
foreach ($back as $key => $val) {
    echo $key . ': ' . gettype($val) . "\n";
}

$null_arr = ['val' => null];
$null_back = unserialize(serialize($null_arr));
echo "null_val: " . gettype($null_back['val']) . "\n";

// --- object serialization ---

echo "\n=== Object Serialization ===\n";

class Point {
    public float $x;
    public float $y;
    public string $label;

    public function __construct(float $x, float $y, string $label = '') {
        $this->x = $x;
        $this->y = $y;
        $this->label = $label;
    }

    public function distanceTo(Point $other): float {
        return sqrt(($this->x - $other->x) ** 2 + ($this->y - $other->y) ** 2);
    }
}

$p = new Point(3.0, 4.0, 'origin-adjacent');
$ser = serialize($p);
echo "Point serialized: " . $ser . "\n";

$p2 = unserialize($ser);
echo "Point class: " . get_class($p2) . "\n";
echo "Point x: " . $p2->x . "\n";
echo "Point y: " . $p2->y . "\n";
echo "Point label: " . $p2->label . "\n";
echo "Distance to origin: " . $p2->distanceTo(new Point(0.0, 0.0)) . "\n";

// --- object with private/protected properties ---

echo "\n=== Visibility Levels ===\n";

class Secret {
    public string $pub = 'public-val';
    protected string $prot = 'protected-val';
    private string $priv = 'private-val';

    public function getAll(): array {
        return [$this->pub, $this->prot, $this->priv];
    }
}

$s = new Secret();
$back = unserialize(serialize($s));
$vals = $back->getAll();
echo "public: " . $vals[0] . "\n";
echo "protected: " . $vals[1] . "\n";
echo "private: " . $vals[2] . "\n";

// --- inheritance serialization ---

echo "\n=== Inheritance Serialization ===\n";

class Shape {
    public string $type;
    public string $color;

    public function __construct(string $type, string $color) {
        $this->type = $type;
        $this->color = $color;
    }

    public function describe(): string {
        return $this->color . ' ' . $this->type;
    }
}

class Circle extends Shape {
    public float $radius;

    public function __construct(float $radius, string $color) {
        parent::__construct('circle', $color);
        $this->radius = $radius;
    }

    public function area(): float {
        return M_PI * $this->radius ** 2;
    }
}

$c = new Circle(5.0, 'blue');
$back = unserialize(serialize($c));
echo "class: " . get_class($back) . "\n";
echo "describe: " . $back->describe() . "\n";
echo "area: " . round($back->area(), 2) . "\n";
echo "instanceof Shape: " . ($back instanceof Shape ? 'yes' : 'no') . "\n";

// --- array of objects ---

echo "\n=== Array of Objects ===\n";

$points = [
    new Point(1.0, 2.0, 'A'),
    new Point(3.0, 4.0, 'B'),
    new Point(5.0, 6.0, 'C'),
];

$back = unserialize(serialize($points));
$labels = array_map(function($p) { return $p->label; }, $back);
echo "labels: " . implode(', ', $labels) . "\n";
echo "count: " . count($back) . "\n";
echo "B distance to C: " . round($back[1]->distanceTo($back[2]), 2) . "\n";

// --- nested objects ---

echo "\n=== Nested Objects ===\n";

class Box {
    public string $name;
    public array $contents;

    public function __construct(string $name, array $contents = []) {
        $this->name = $name;
        $this->contents = $contents;
    }

    public function itemCount(): int {
        return count($this->contents);
    }
}

$box = new Box('outer', [
    new Box('inner-1', [new Point(0.0, 0.0, 'center')]),
    new Box('inner-2', [new Point(1.0, 1.0, 'offset')]),
]);

$back = unserialize(serialize($box));
echo "box: " . $back->name . "\n";
echo "items: " . $back->itemCount() . "\n";
echo "inner-1 contents: " . $back->contents[0]->contents[0]->label . "\n";
echo "inner-2 contents: " . $back->contents[1]->contents[0]->label . "\n";

// --- json roundtrips ---

echo "\n=== JSON Roundtrips ===\n";

$data = [
    'name' => 'test',
    'values' => [1, 2, 3],
    'nested' => ['a' => true, 'b' => null, 'c' => 3.14],
    'empty_arr' => [],
];

$json = json_encode($data);
echo "json: " . $json . "\n";
$back = json_decode($json, true);
echo "name: " . $back['name'] . "\n";
echo "values count: " . count($back['values']) . "\n";
echo "nested.a: " . ($back['nested']['a'] ? 'true' : 'false') . "\n";
echo "nested.b is null: " . (is_null($back['nested']['b']) ? 'yes' : 'no') . "\n";
echo "nested.c: " . $back['nested']['c'] . "\n";

// --- large nested structure ---

echo "\n=== Large Nested Structure ===\n";

$tree = [];
for ($i = 0; $i < 5; $i++) {
    $children = [];
    for ($j = 0; $j < 3; $j++) {
        $children[] = ['parent' => $i, 'child' => $j, 'label' => "node-$i-$j"];
    }
    $tree[] = ['id' => $i, 'children' => $children];
}

$back = unserialize(serialize($tree));
echo "nodes: " . count($back) . "\n";
echo "first children: " . count($back[0]['children']) . "\n";
echo "label [2][1]: " . $back[2]['children'][1]['label'] . "\n";
echo "parent [3][0]: " . $back[3]['children'][0]['parent'] . "\n";

echo "\nDone.\n";
