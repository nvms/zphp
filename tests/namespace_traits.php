<?php
// covers: trait methods in namespaced classes, trait name resolution via use aliases

namespace App\Traits;

trait Greeter {
    public function greet() {
        return "hello from " . $this->name;
    }

    public static function staticGreet() {
        return "static hello";
    }
}

trait Logger {
    public function log($msg) {
        return "[LOG] $msg";
    }
}

namespace App\Models;

use App\Traits\Greeter;
use App\Traits\Logger;

class User {
    use Greeter, Logger;

    public $name;

    public function __construct($name) {
        $this->name = $name;
    }
}

$user = new User("Alice");
echo $user->greet() . "\n";
echo $user->log("test") . "\n";
echo User::staticGreet() . "\n";

// trait using another trait
namespace App\Traits;

trait Combined {
    use Greeter;
    use Logger;

    public function both() {
        return $this->greet() . " " . $this->log("combined");
    }
}

namespace App\Models;

use App\Traits\Combined;

class Admin {
    use Combined;

    public $name;

    public function __construct($name) {
        $this->name = $name;
    }
}

$admin = new Admin("Bob");
echo $admin->greet() . "\n";
echo $admin->both() . "\n";
