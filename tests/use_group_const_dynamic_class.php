<?php
namespace App\Models;

class User {
    public function __construct(public string $name) {}
}

class Post {
    public function __construct(public string $title) {}
}

const VERSION = "1.0";

function helper(): string { return "from App\\Models"; }

namespace App\Controllers;

use App\Models\{User as U, Post};
use function App\Models\helper;
use const App\Models\VERSION;

$u = new U("alice");
echo $u->name, "\n";

$p = new Post("hello");
echo $p->title, "\n";

echo helper(), "\n";
echo VERSION, "\n";

$cls = "\\App\\Models\\User";
$u = new $cls("dynamic");
echo $u->name, "\n";

namespace App\Math;

const PI = 3.14;
const E = 2.71;

function add(int $a, int $b): int { return $a + $b; }
function mul(int $a, int $b): int { return $a * $b; }

namespace App\Compute;

use const App\Math\{PI, E};
use function App\Math\{add, mul};

echo PI, " ", E, "\n";
echo add(3, 4), "\n";
echo mul(5, 6), "\n";
echo \App\Math\PI, "\n";

$cls = "App\\Models\\User";
$u = new $cls("noprefix");
echo $u->name, "\n";
