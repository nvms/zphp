<?php
// covers: namespaced names accepting leading-backslash equivalence across
//   class/function/interface/trait checks, reflection, instanceof, new, is_a,
//   class_parents, class_implements, get_parent_class, property_exists,
//   namespaced const resolution + use-const, ReflectionClass::getNamespaceName

namespace App\Models;

class User {
    public function __construct(public string $name = 'anon') {}
    public function greet(string $who): string { return "hi $who, I'm $this->name"; }
}

class Post {
    public function __construct(public string $title = 'untitled') {}
}

const VERSION = "2.0";

namespace App\Domain;
interface Loggable { public function log(): string; }
class Service implements Loggable {
    public function log(): string { return "service-log"; }
}
abstract class Base { abstract public function kind(): string; }
class Child extends Base {
    public function kind(): string { return "child"; }
}

namespace App;
use App\Models\{User, Post};
use const App\Models\VERSION;

echo "=== bare const resolves via use-const ===\n";
echo VERSION . "\n";
echo \App\Models\VERSION . "\n";

echo "\n=== class_exists with both forms ===\n";
var_dump(class_exists('App\\Models\\User'));
var_dump(class_exists('\\App\\Models\\User'));

echo "\n=== instanceof both forms ===\n";
$u = new User('alice');
var_dump($u instanceof \App\Models\User);
var_dump($u instanceof User);

echo "\n=== is_a both forms ===\n";
var_dump(is_a($u, 'App\\Models\\User'));
var_dump(is_a($u, '\\App\\Models\\User'));

echo "\n=== new \$dynamic with leading backslash ===\n";
$cls = '\\App\\Models\\User';
$dyn = new $cls('bob');
echo $dyn->greet('charlie') . "\n";

echo "\n=== interface_exists / trait_exists with both forms ===\n";
var_dump(interface_exists('App\\Domain\\Loggable'));
var_dump(interface_exists('\\App\\Domain\\Loggable'));

echo "\n=== get_parent_class with both forms ===\n";
echo get_parent_class('App\\Domain\\Child') . "\n";
echo get_parent_class('\\App\\Domain\\Child') . "\n";

echo "\n=== class_parents / class_implements with both forms ===\n";
print_r(array_keys(class_parents('\\App\\Domain\\Child')));
print_r(array_keys(class_implements('\\App\\Domain\\Service')));

echo "=== property_exists with both forms ===\n";
var_dump(property_exists('App\\Models\\User', 'name'));
var_dump(property_exists('\\App\\Models\\User', 'name'));

echo "\n=== ReflectionClass with both forms + namespace info ===\n";
$rc = new \ReflectionClass('\\App\\Models\\User');
echo "name: " . $rc->getName() . "\n";
echo "short: " . $rc->getShortName() . "\n";
echo "ns: " . $rc->getNamespaceName() . "\n";
echo "inNamespace: " . ($rc->inNamespace() ? "yes" : "no") . "\n";

echo "\n=== ReflectionMethod with both forms ===\n";
$rm = new \ReflectionMethod('\\App\\Models\\User', 'greet');
echo "method: " . $rm->getName() . "\n";
echo "declaring: " . $rm->getDeclaringClass()->getName() . "\n";

echo "\n=== variable function with leading backslash ===\n";
namespace App\Util;
function greet(string $who): string { return "from-util-$who"; }

namespace App;
$fn = '\\App\\Util\\greet';
echo $fn('test') . "\n";
echo function_exists('\\App\\Util\\greet') ? "yes\n" : "no\n";
var_dump(is_callable('\\App\\Util\\greet'));

echo "\ndone\n";
