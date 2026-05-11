<?php
namespace App\Lib;

class Logger {
    public function log(string $msg): string { return "[App\\Lib\\Logger] $msg"; }
}

function helper(int $x): int { return $x * 2; }

const ANSWER = 42;

class Config {
    public function get(string $k): string { return "config:$k"; }
}

class User {
    public function __construct(public string $name) {}
    public function describe(): string { return "User:{$this->name}"; }
}
