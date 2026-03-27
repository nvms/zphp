<?php
// covers: Closure::bind, Closure::bindTo, Closure::call,
//   Closure::fromCallable, closures with $this, captured variables,
//   closure parameters, method-defined closures, rebinding

class RouteGroup {
    public string $prefix;
    public array $routes = [];

    public function __construct(string $prefix) {
        $this->prefix = $prefix;
    }

    public function get(string $path, string $handler): void {
        $this->routes[] = "GET " . $this->prefix . $path . " -> " . $handler;
    }

    public function post(string $path, string $handler): void {
        $this->routes[] = "POST " . $this->prefix . $path . " -> " . $handler;
    }
}

class Router {
    public array $groups = [];

    public function group(string $prefix, Closure $callback): void {
        $group = new RouteGroup($prefix);
        $bound = Closure::bind($callback, $group);
        $bound();
        $this->groups[] = $group;
    }

    public function dump(): void {
        foreach ($this->groups as $group) {
            foreach ($group->routes as $route) {
                echo $route . "\n";
            }
        }
    }
}

$router = new Router();

$router->group("/api/v1", function() {
    $this->get("/users", "UserController@index");
    $this->post("/users", "UserController@store");
    $this->get("/posts", "PostController@index");
});

$router->group("/admin", function() {
    $this->get("/dashboard", "AdminController@dashboard");
    $this->post("/settings", "AdminController@update");
});

$router->dump();

// macro system using Closure::bind
class Collection {
    public array $items;
    public static array $macros = [];

    public function __construct(array $items) {
        $this->items = $items;
    }

    public static function macro(string $name, Closure $fn): void {
        self::$macros[$name] = $fn;
    }

    public function __call(string $name, array $args): mixed {
        if (isset(self::$macros[$name])) {
            $bound = Closure::bind(self::$macros[$name], $this);
            return call_user_func_array($bound, $args);
        }
        return null;
    }
}

Collection::macro('sum', function() {
    $total = 0;
    foreach ($this->items as $item) {
        $total += $item;
    }
    return $total;
});

Collection::macro('avg', function() {
    $total = 0;
    foreach ($this->items as $item) {
        $total += $item;
    }
    return $total / count($this->items);
});

Collection::macro('contains', function(mixed $value) {
    foreach ($this->items as $item) {
        if ($item === $value) return true;
    }
    return false;
});

$nums = new Collection([10, 20, 30, 40]);
echo "sum: " . $nums->sum() . "\n";
echo "avg: " . $nums->avg() . "\n";
echo "has 20: " . ($nums->contains(20) ? "yes" : "no") . "\n";
echo "has 99: " . ($nums->contains(99) ? "yes" : "no") . "\n";

// bindTo for middleware-style pattern
class Request {
    public string $method;
    public string $path;
    public array $headers;

    public function __construct(string $method, string $path, array $headers = []) {
        $this->method = $method;
        $this->path = $path;
        $this->headers = $headers;
    }
}

class MiddlewarePipeline {
    public array $pipes = [];

    public function through(Closure $middleware): self {
        $this->pipes[] = $middleware;
        return $this;
    }

    public function process(Request $request): string {
        $result = "OK";
        foreach ($this->pipes as $pipe) {
            $bound = $pipe->bindTo($request);
            $check = $bound();
            if ($check !== null) {
                $result = $check;
            }
        }
        return $result;
    }
}

$pipeline = new MiddlewarePipeline();
$pipeline->through(function() {
    echo "auth check: " . $this->path . "\n";
    return null;
});
$pipeline->through(function() {
    echo "logging: " . $this->method . " " . $this->path . "\n";
    return null;
});

$request = new Request("GET", "/api/users", ["Accept" => "application/json"]);
$result = $pipeline->process($request);
echo "result: $result\n";

// Closure::call - bind and invoke in one step
class Config {
    public array $data;
    public function __construct(array $data) {
        $this->data = $data;
    }
}

$reader = function(string $key) {
    return $this->data[$key] ?? "not found";
};

$config = new Config(["host" => "localhost", "port" => "5432"]);
echo $reader->call($config, "host") . "\n";
echo $reader->call($config, "port") . "\n";
echo $reader->call($config, "missing") . "\n";

// Closure::fromCallable
function double(int $n): int { return $n * 2; }

$fn = Closure::fromCallable('double');
echo $fn(21) . "\n";

// captured vars preserved across rebinding
$multiplier = 3;
$multiply = function(int $n) use ($multiplier) {
    return $n * $multiplier + count($this->items);
};

$a = new Collection([1, 2, 3]);
$b = new Collection([1, 2, 3, 4, 5]);

$boundA = Closure::bind($multiply, $a);
$boundB = Closure::bind($multiply, $b);

echo $boundA(10) . "\n";
echo $boundB(10) . "\n";
