<?php
// covers: __callStatic, static properties, late static binding (static::),
//   inheritance, interface implementation, array methods, string interpolation,
//   abstract-like patterns, service container integration with reflection

class Container {
    private static array $bindings = [];
    private static array $instances = [];

    public static function bind(string $abstract, object $instance): void {
        self::$instances[$abstract] = $instance;
    }

    public static function resolve(string $abstract): object {
        return self::$instances[$abstract] ?? new \stdClass();
    }
}

class Facade {
    protected static string $accessor = '';

    public static function __callStatic(string $method, array $args): mixed {
        $instance = Container::resolve(static::$accessor);
        return call_user_func_array([$instance, $method], $args);
    }
}

// concrete implementations
class QueryBuilder {
    private string $table = '';
    private array $wheres = [];
    private array $selects = ['*'];
    private ?int $limitVal = null;

    public function table(string $name): self {
        $this->table = $name;
        return $this;
    }

    public function select(string ...$cols): self {
        $this->selects = $cols;
        return $this;
    }

    public function where(string $col, string $op, mixed $val): self {
        $this->wheres[] = "$col $op '$val'";
        return $this;
    }

    public function limit(int $n): self {
        $this->limitVal = $n;
        return $this;
    }

    public function toSql(): string {
        $sql = "SELECT " . implode(", ", $this->selects) . " FROM " . $this->table;
        if (count($this->wheres) > 0) {
            $sql .= " WHERE " . implode(" AND ", $this->wheres);
        }
        if ($this->limitVal !== null) {
            $sql .= " LIMIT " . $this->limitVal;
        }
        return $sql;
    }
}

class CacheStore {
    private array $data = [];

    public function get(string $key, mixed $default = null): mixed {
        return $this->data[$key] ?? $default;
    }

    public function put(string $key, mixed $value, int $ttl = 3600): bool {
        $this->data[$key] = $value;
        return true;
    }

    public function has(string $key): bool {
        return isset($this->data[$key]);
    }

    public function forget(string $key): bool {
        unset($this->data[$key]);
        return true;
    }
}

class EventDispatcher {
    private array $listeners = [];

    public function listen(string $event, callable $listener): void {
        $this->listeners[$event][] = $listener;
    }

    public function dispatch(string $event, array $payload = []): int {
        $count = 0;
        foreach ($this->listeners[$event] ?? [] as $listener) {
            call_user_func($listener, $payload);
            $count++;
        }
        return $count;
    }
}

// facades
class DB extends Facade {
    protected static string $accessor = 'db';
}

class Cache extends Facade {
    protected static string $accessor = 'cache';
}

class Event extends Facade {
    protected static string $accessor = 'events';
}

// wire up container
Container::bind('db', new QueryBuilder());
Container::bind('cache', new CacheStore());
Container::bind('events', new EventDispatcher());

// use facades - every method call goes through __callStatic
$query = DB::table("users")
    ->where("active", "=", "1")
    ->where("role", "=", "admin")
    ->select("id", "name", "email")
    ->limit(10);
echo $query->toSql() . "\n";

Cache::put("user:1", "Alice");
Cache::put("user:2", "Bob");
echo Cache::get("user:1") . "\n";
echo Cache::has("user:2") ? "cached" : "miss";
echo "\n";
Cache::forget("user:2");
echo Cache::has("user:2") ? "cached" : "miss";
echo "\n";

$log = [];
Event::listen("user.created", function ($data) use (&$log) {
    $log[] = "user created: " . $data['name'];
});
Event::listen("user.created", function ($data) use (&$log) {
    $log[] = "welcome email to: " . $data['name'];
});

$fired = Event::dispatch("user.created", ["name" => "Charlie"]);
echo "fired $fired listeners\n";
foreach ($log as $entry) {
    echo $entry . "\n";
}

// dynamic class resolution
$facades = ['DB', 'Cache'];
foreach ($facades as $f) {
    $rc = new ReflectionClass($f);
    echo $rc->getName() . " extends " . $rc->getParentClass()->getName() . "\n";
    echo $rc->hasMethod('__callStatic') ? "has __callStatic" : "no __callStatic";
    echo "\n";
}
