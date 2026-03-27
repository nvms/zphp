<?php

class Facade {
    protected static string $target = '';

    public static function __callStatic(string $name, array $arguments): string {
        return static::$target . "::" . $name . "(" . implode(", ", $arguments) . ")";
    }
}

class DB extends Facade {
    protected static string $target = 'Database';
}

class Cache extends Facade {
    protected static string $target = 'CacheStore';
}

// basic __callStatic
echo DB::table("users") . "\n";
echo DB::where("id", "1") . "\n";
echo Cache::get("key") . "\n";
echo Cache::put("key", "value", "60") . "\n";

// with no args
echo DB::all() . "\n";

// chaining pattern (each returns a string here)
echo DB::select("name", "email") . "\n";

// dynamic class name
$class = 'DB';
echo $class::find("42") . "\n";

// __callStatic doesn't interfere with real static methods
class Router {
    private static array $routes = [];

    public static function get(string $path, string $handler): void {
        self::$routes[] = "GET $path -> $handler";
    }

    public static function post(string $path, string $handler): void {
        self::$routes[] = "POST $path -> $handler";
    }

    public static function __callStatic(string $name, array $args): string {
        return "custom: $name";
    }

    public static function dump(): void {
        foreach (self::$routes as $r) {
            echo $r . "\n";
        }
    }
}

Router::get("/users", "UserController@index");
Router::post("/users", "UserController@store");
Router::dump();
echo Router::patch("/users/1", "UserController@update") . "\n";

// __callStatic with spread
class Proxy {
    public static function __callStatic(string $name, array $args): string {
        return "proxy:$name:" . count($args);
    }
}

$args = ["a", "b", "c"];
echo Proxy::forward(...$args) . "\n";

// inheritance - child inherits __callStatic
class BaseModel {
    public static function __callStatic(string $name, array $args): string {
        return "model:" . $name;
    }
}

class User extends BaseModel {}

echo User::find() . "\n";
echo User::where() . "\n";
