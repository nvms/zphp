<?php

// tests for stdlib sprint fixes

// str_replace with array needle
echo str_replace(['a','e','i','o','u'], '*', 'Hello World') . "\n";
echo str_replace(['foo','bar'], 'X', 'foo bar baz') . "\n";
echo str_replace(['a','e'], ['@','3'], 'apple') . "\n";

// array comparison (== and ===)
$a = [1, 2, 3];
$b = [1, 2, 3];
echo ($a === $b ? 'true' : 'false') . "\n";
echo ($a == $b ? 'true' : 'false') . "\n";
echo ([1, '2'] == [1, 2] ? 'true' : 'false') . "\n";
echo ([1, '2'] === [1, 2] ? 'true' : 'false') . "\n";

// array_splice re-indexing
$arr = [1, 2, 3, 4, 5];
array_splice($arr, 1, 2, [20, 30]);
echo json_encode($arr) . "\n";

// preg_split with limit
echo json_encode(preg_split('/,/', 'a,b,c,d', 3)) . "\n";

// array_map with null callback (zip)
echo json_encode(array_map(null, [1,2,3], [4,5,6])) . "\n";

// method named 'use' (semi-reserved keyword)
class Middleware {
    public function use(string $name): string {
        return "using $name";
    }
    public function list(): string {
        return "listing";
    }
    public function match(string $x): string {
        return "matching $x";
    }
}
$mw = new Middleware();
echo $mw->use("auth") . "\n";
echo $mw->list() . "\n";
echo $mw->match("route") . "\n";

// private property access from closure inside method
class Config {
    private array $data = [];

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function get(string $key): string {
        $fn = function() use ($key) {
            return $this->data[$key] ?? 'missing';
        };
        return $fn();
    }

    public function transform(callable $fn): array {
        return array_map(function($v) use ($fn) {
            return $fn($v);
        }, $this->data);
    }
}

$config = new Config(['host' => 'localhost', 'port' => '3306']);
echo $config->get('host') . "\n";
echo $config->get('missing') . "\n";
echo json_encode($config->transform('strtoupper')) . "\n";
