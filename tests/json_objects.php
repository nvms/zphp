<?php

class User {
    public string $name = "Alice";
    public int $age = 30;
    private string $password = "secret";
    protected string $email = "alice@test.com";
}

$u = new User();
echo json_encode($u) . "\n";
echo json_encode($u, JSON_PRETTY_PRINT) . "\n";

// nested objects
class Post {
    public string $title = "Hello";
    public ?User $author = null;
}

$p = new Post();
$p->author = $u;
echo json_encode($p) . "\n";

// object with no public properties
class Secret {
    private string $key = "hidden";
}
echo json_encode(new Secret()) . "\n";

// dynamic properties
class Box {
    public string $label = "box";
}
$b = new Box();
echo json_encode($b) . "\n";

// JsonSerializable
class Point implements JsonSerializable {
    private float $x;
    private float $y;
    public function __construct(float $x, float $y) {
        $this->x = $x;
        $this->y = $y;
    }
    public function jsonSerialize(): array {
        return ['x' => $this->x, 'y' => $this->y];
    }
}

echo json_encode(new Point(1.5, 2.5)) . "\n";

// array of objects
$users = [new User(), new User()];
$users[1]->name = "Bob";
$users[1]->age = 25;
echo json_encode($users) . "\n";
