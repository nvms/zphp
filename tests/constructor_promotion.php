<?php

// basic constructor property promotion
class Point {
    public function __construct(
        public float $x,
        public float $y
    ) {}
}

$p = new Point(3.0, 4.0);
echo $p->x . "\n";
echo $p->y . "\n";

// mixed promoted and regular properties
class User {
    public $active = true;

    public function __construct(
        public string $name,
        public string $email,
        private int $age = 0
    ) {}

    public function describe() {
        return $this->name . " <" . $this->email . "> age:" . $this->age;
    }
}

$u = new User("Alice", "alice@example.com", 30);
echo $u->name . "\n";
echo $u->email . "\n";
echo $u->describe() . "\n";

// with defaults
$u2 = new User("Bob", "bob@test.com");
echo $u2->describe() . "\n";

// promoted with body logic
class Config {
    public function __construct(
        public string $host,
        public int $port = 8080
    ) {
        $this->host = strtoupper($this->host);
    }
}

$c = new Config("localhost");
echo $c->host . "\n";
echo $c->port . "\n";
