<?php
// covers: array callables ([$obj, "method"], ["Class", "static"]),
//   string function callables, closure callables, pattern matching,
//   multi-level parameter extraction, string manipulation (explode, trim)

class Router
{
    private array $routes = [];

    public function add(string $method, string $pattern, callable $handler): void
    {
        $this->routes[] = [
            "method" => $method,
            "pattern" => $pattern,
            "handler" => $handler,
        ];
    }

    public function get(string $pattern, callable $handler): void
    {
        $this->add("GET", $pattern, $handler);
    }

    public function post(string $pattern, callable $handler): void
    {
        $this->add("POST", $pattern, $handler);
    }

    public function dispatch(string $method, string $uri): string
    {
        foreach ($this->routes as $route) {
            if ($route["method"] !== $method) continue;

            $params = $this->match($route["pattern"], $uri);
            if ($params !== null) {
                $handler = $route["handler"];
                return ($handler)($params);
            }
        }
        return "404 Not Found";
    }

    private function match(string $pattern, string $uri): ?array
    {
        $patternParts = explode("/", trim($pattern, "/"));
        $uriParts = explode("/", trim($uri, "/"));

        if (count($patternParts) !== count($uriParts)) return null;

        $params = [];
        for ($i = 0; $i < count($patternParts); $i++) {
            $p = $patternParts[$i];
            $u = $uriParts[$i];

            if (strlen($p) > 0 && $p[0] === ":") {
                $params[substr($p, 1)] = $u;
            } elseif ($p !== $u) {
                return null;
            }
        }
        return $params;
    }
}

class UserController
{
    public static function index(array $params): string
    {
        return "user list";
    }

    public static function show(array $params): string
    {
        return "user:" . $params["id"];
    }

    public function profile(array $params): string
    {
        return "profile:" . $params["id"];
    }
}

$router = new Router();

// closure handler
$router->get("/", function ($params) {
    return "home";
});

// string callable
$router->get("/about", function ($params) {
    return "about page";
});

// static method via array callable
$router->get("/users", ["UserController", "index"]);
$router->get("/users/:id", ["UserController", "show"]);

// instance method via array callable
$ctrl = new UserController();
$router->get("/profile/:id", [$ctrl, "profile"]);

// route with multiple params
$router->get("/posts/:year/:slug", function ($params) {
    return "post:" . $params["year"] . "/" . $params["slug"];
});

echo $router->dispatch("GET", "/") . "\n";
echo $router->dispatch("GET", "/about") . "\n";
echo $router->dispatch("GET", "/users") . "\n";
echo $router->dispatch("GET", "/users/42") . "\n";
echo $router->dispatch("GET", "/profile/7") . "\n";
echo $router->dispatch("GET", "/posts/2024/hello-world") . "\n";
echo $router->dispatch("GET", "/missing") . "\n";
echo $router->dispatch("POST", "/users") . "\n";

echo "done\n";
