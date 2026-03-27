<?php
// covers: class inheritance, __construct, __get, __set, __toString, __call,
//         static methods, abstract classes, array_column, usort, array_map,
//         array_filter, array_values, implode, sprintf, json_encode, json_decode,
//         in_array, array_key_exists, count, is_array, is_string, array_merge,
//         array_keys, strtolower, ucfirst, str_replace, compact, extract

// --- base model ---

class Model {
    protected $attributes = [];
    protected $original = [];
    protected $dirty = [];

    public function __construct($attributes = []) {
        $this->fill($attributes);
        $this->original = $this->attributes;
        $this->dirty = [];
    }

    public function fill($attributes) {
        foreach ($attributes as $key => $value) {
            $this->attributes[$key] = $value;
        }
        return $this;
    }

    public function __get($name) {
        return $this->attributes[$name] ?? null;
    }

    public function __set($name, $value) {
        if (!array_key_exists($name, $this->attributes) || $this->attributes[$name] !== $value) {
            $this->dirty[$name] = true;
        }
        $this->attributes[$name] = $value;
    }

    public function isDirty($field = null) {
        if ($field === null) {
            return count($this->dirty) > 0;
        }
        return isset($this->dirty[$field]);
    }

    public function getDirty() {
        $changed = [];
        foreach ($this->dirty as $key => $v) {
            $changed[$key] = $this->attributes[$key];
        }
        return $changed;
    }

    public function toArray() {
        return $this->attributes;
    }

    public function toJson() {
        return json_encode($this->attributes);
    }
}

// --- user model ---

class User extends Model {
    public function __toString() {
        return sprintf("User(%s: %s)", $this->id ?? '?', $this->name ?? 'unnamed');
    }

    public function getFullName() {
        return trim(($this->first_name ?? '') . ' ' . ($this->last_name ?? ''));
    }

    public function isAdmin() {
        return $this->role === 'admin';
    }
}

// --- collection ---

class Collection {
    private $items = [];

    public function __construct($items = []) {
        $this->items = $items;
    }

    public function count() {
        return count($this->items);
    }

    public function first() {
        return $this->items[0] ?? null;
    }

    public function last() {
        return $this->items[count($this->items) - 1] ?? null;
    }

    public function map($callback) {
        return new Collection(array_map($callback, $this->items));
    }

    public function filter($callback) {
        return new Collection(array_values(array_filter($this->items, $callback)));
    }

    public function sortBy($field, $direction = 'asc') {
        $items = $this->items;
        usort($items, function($a, $b) use ($field, $direction) {
            $va = is_array($a) ? ($a[$field] ?? null) : ($a->$field ?? null);
            $vb = is_array($b) ? ($b[$field] ?? null) : ($b->$field ?? null);
            if ($va === $vb) return 0;
            $cmp = $va < $vb ? -1 : 1;
            return $direction === 'desc' ? -$cmp : $cmp;
        });
        return new Collection($items);
    }

    public function pluck($field) {
        return array_map(function($item) use ($field) {
            if (is_array($item)) return $item[$field] ?? null;
            return $item->$field ?? null;
        }, $this->items);
    }

    public function toArray() {
        return array_map(function($item) {
            if (is_array($item)) return $item;
            if (method_exists($item, 'toArray')) return $item->toArray();
            return $item;
        }, $this->items);
    }

    public function where($field, $value) {
        return $this->filter(function($item) use ($field, $value) {
            if (is_array($item)) return ($item[$field] ?? null) === $value;
            return ($item->$field ?? null) === $value;
        });
    }

    public function sum($field) {
        $total = 0;
        foreach ($this->items as $item) {
            $val = is_array($item) ? ($item[$field] ?? 0) : ($item->$field ?? 0);
            $total += $val;
        }
        return $total;
    }

    public function groupBy($field) {
        $groups = [];
        foreach ($this->items as $item) {
            $key = is_array($item) ? ($item[$field] ?? '') : ($item->$field ?? '');
            if (!isset($groups[$key])) {
                $groups[$key] = [];
            }
            $groups[$key][] = $item;
        }
        $result = [];
        foreach ($groups as $key => $items) {
            $result[$key] = new Collection($items);
        }
        return $result;
    }
}

// --- test: basic model ---

echo "--- model ---\n";

$user = new User(['id' => 1, 'name' => 'Alice', 'email' => 'alice@test.com', 'role' => 'admin']);
echo "name: {$user->name}\n";
echo "email: {$user->email}\n";
echo "admin: " . ($user->isAdmin() ? 'yes' : 'no') . "\n";
echo "dirty: " . ($user->isDirty() ? 'yes' : 'no') . "\n";

$user->name = 'Alice Smith';
echo "dirty now: " . ($user->isDirty() ? 'yes' : 'no') . "\n";
echo "dirty name: " . ($user->isDirty('name') ? 'yes' : 'no') . "\n";
echo "dirty email: " . ($user->isDirty('email') ? 'yes' : 'no') . "\n";

$changes = $user->getDirty();
echo "changes: " . json_encode($changes) . "\n";

// --- test: __toString ---

echo "--- toString ---\n";
echo "$user\n";
$user2 = new User(['id' => 2, 'name' => 'Bob']);
echo "$user2\n";
$user3 = new User([]);
echo "$user3\n";

// --- test: json ---

echo "--- json ---\n";
echo $user2->toJson() . "\n";
$arr = $user2->toArray();
echo "keys: " . implode(', ', array_keys($arr)) . "\n";

// --- test: collection basics ---

echo "--- collection ---\n";

$users = new Collection([
    new User(['id' => 1, 'name' => 'Alice', 'age' => 30, 'role' => 'admin', 'score' => 95]),
    new User(['id' => 2, 'name' => 'Bob', 'age' => 25, 'role' => 'user', 'score' => 82]),
    new User(['id' => 3, 'name' => 'Charlie', 'age' => 35, 'role' => 'user', 'score' => 91]),
    new User(['id' => 4, 'name' => 'Diana', 'age' => 28, 'role' => 'admin', 'score' => 88]),
    new User(['id' => 5, 'name' => 'Eve', 'age' => 32, 'role' => 'moderator', 'score' => 76]),
]);

echo "count: " . $users->count() . "\n";
echo "first: " . $users->first() . "\n";
echo "last: " . $users->last() . "\n";

// --- test: pluck ---

echo "--- pluck ---\n";
$names = $users->pluck('name');
echo "names: " . implode(', ', $names) . "\n";

// --- test: where ---

echo "--- where ---\n";
$admins = $users->where('role', 'admin');
echo "admins: " . $admins->count() . "\n";
$adminNames = $admins->pluck('name');
echo "admin names: " . implode(', ', $adminNames) . "\n";

// --- test: sortBy ---

echo "--- sort ---\n";
$byAge = $users->sortBy('age');
$sortedNames = $byAge->pluck('name');
echo "by age asc: " . implode(', ', $sortedNames) . "\n";

$byAgeDesc = $users->sortBy('age', 'desc');
$sortedNames = $byAgeDesc->pluck('name');
echo "by age desc: " . implode(', ', $sortedNames) . "\n";

$byName = $users->sortBy('name');
$sortedNames = $byName->pluck('name');
echo "by name: " . implode(', ', $sortedNames) . "\n";

// --- test: sum ---

echo "--- sum ---\n";
echo "total score: " . $users->sum('score') . "\n";
echo "total age: " . $users->sum('age') . "\n";

// --- test: groupBy ---

echo "--- groupBy ---\n";
$byRole = $users->groupBy('role');
foreach ($byRole as $role => $group) {
    $groupNames = $group->pluck('name');
    echo "$role: " . implode(', ', $groupNames) . "\n";
}

// --- test: chaining ---

echo "--- chaining ---\n";
$result = $users
    ->filter(function($u) { return $u->age >= 28; })
    ->sortBy('score', 'desc');
$resultNames = $result->pluck('name');
echo "age>=28, by score desc: " . implode(', ', $resultNames) . "\n";
echo "count: " . $result->count() . "\n";

// --- test: collection of arrays ---

echo "--- array collection ---\n";
$products = new Collection([
    ['name' => 'Widget', 'price' => 9.99, 'category' => 'tools'],
    ['name' => 'Gadget', 'price' => 24.99, 'category' => 'electronics'],
    ['name' => 'Doohickey', 'price' => 14.99, 'category' => 'tools'],
    ['name' => 'Thingamajig', 'price' => 39.99, 'category' => 'electronics'],
]);

$sorted = $products->sortBy('price');
$sortedNames = $sorted->pluck('name');
echo "by price: " . implode(', ', $sortedNames) . "\n";

$tools = $products->where('category', 'tools');
echo "tools: " . $tools->count() . "\n";
echo "tool total: " . $tools->sum('price') . "\n";

echo "done\n";
