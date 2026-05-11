<?php
namespace App\Main;

require __DIR__ . "/namespaces_use_alias_function_const_lib.php";

use App\Lib\Logger;
use App\Lib\Config as Cfg;
use App\Lib\User;
use function App\Lib\helper;

echo (new Logger)->log("hello"), "\n";
echo (new Cfg)->get("k1"), "\n";
echo helper(5), "\n";
echo \App\Lib\ANSWER, "\n";

$u = new User("alice");
echo $u->describe(), "\n";

$cls = "App\\Lib\\Logger";
echo (new $cls)->log("dynamic"), "\n";

echo \App\Lib\helper(10), "\n";
echo \App\Lib\ANSWER, "\n";
$f = new \App\Lib\Config;
echo $f->get("k2"), "\n";

class LocalThing {
    public function greet(): string { return "from-App\\Main\\LocalThing"; }
}
$t = new LocalThing;
echo $t->greet(), "\n";
echo get_class($t), "\n";

namespace App\Main\Sub;

class Nested {
    public function name(): string { return __CLASS__; }
}
$n = new Nested;
echo $n->name(), "\n";

echo \App\Lib\helper(3), "\n";
$cfg = new \App\Lib\Config;
echo $cfg->get("global"), "\n";

echo __NAMESPACE__, "\n";
