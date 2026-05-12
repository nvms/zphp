<?php
// covers: FQN (leading-backslash) usage across all PHP language positions -
//   type hints, union types, return types, catch, instanceof, static calls,
//   const access, new, multi-catch, throw, getPrevious chain.

namespace App\Models;
class User { public function __construct(public string $name = 'u') {} }
class Admin { public function __construct(public string $kind = 'admin') {} }

namespace App\Errors;
class CustomError extends \RuntimeException {}
class SpecialError extends \LogicException {}

namespace App\Util;
class Helpers {
    public static function shout(string $s): string { return strtoupper($s); }
    public const VERSION = '1.2.3';
}

namespace App\Service;
use App\Models\User;

echo "=== FQN type hint ===\n";
function takeUser(\App\Models\User $u): string { return $u->name; }
echo takeUser(new User('alice')) . "\n";

echo "\n=== FQN nullable type ===\n";
function maybeAdmin(?\App\Models\Admin $a): string { return $a?->kind ?? 'none'; }
echo maybeAdmin(null) . "\n";
echo maybeAdmin(new \App\Models\Admin('super')) . "\n";

echo "\n=== FQN union type ===\n";
function userOrAdmin(\App\Models\User|\App\Models\Admin $x): string {
    return $x instanceof \App\Models\Admin ? "A:$x->kind" : "U:$x->name";
}
echo userOrAdmin(new User('bob')) . "\n";
echo userOrAdmin(new \App\Models\Admin('owner')) . "\n";

echo "\n=== FQN in match (true) arms ===\n";
function describe(object $x): string {
    return match (true) {
        $x instanceof \App\Models\User => 'user: ' . $x->name,
        $x instanceof \App\Models\Admin => 'admin: ' . $x->kind,
        default => 'other',
    };
}
echo describe(new User('alice')) . "\n";
echo describe(new \App\Models\Admin('root')) . "\n";

echo "\n=== FQN multi-catch + use-alias-catch ===\n";
function may_fail(int $kind) {
    if ($kind === 1) throw new \App\Errors\CustomError('custom-err');
    if ($kind === 2) throw new \App\Errors\SpecialError('special-err');
    if ($kind === 3) throw new \RuntimeException('generic-rt');
    return 'no-throw';
}
for ($i = 1; $i <= 3; $i++) {
    try {
        may_fail($i);
    } catch (\App\Errors\CustomError | \App\Errors\SpecialError $e) {
        echo "  app: " . $e->getMessage() . "\n";
    } catch (\RuntimeException $e) {
        echo "  rt: " . $e->getMessage() . "\n";
    }
}

echo "\n=== exception chain across FQN catches ===\n";
function rethrow_chain() {
    try {
        throw new \App\Errors\CustomError('chained-inner');
    } catch (\App\Errors\CustomError $e) {
        throw new \RuntimeException('wrapped: ' . $e->getMessage(), 0, $e);
    }
}
try {
    rethrow_chain();
} catch (\RuntimeException $e) {
    echo "outer: " . $e->getMessage() . "\n";
    echo "inner: " . $e->getPrevious()->getMessage() . "\n";
    echo "inner class: " . get_class($e->getPrevious()) . "\n";
}

echo "\n=== FQN static call + const access ===\n";
echo \App\Util\Helpers::shout('hello') . "\n";
echo \App\Util\Helpers::VERSION . "\n";

echo "\n=== variable + FQN dynamic class ===\n";
$cls = '\\App\\Models\\User';
$obj = new $cls('carol');
echo $obj->name . "\n";
echo "is_a? " . (is_a($obj, '\\App\\Models\\User') ? 'yes' : 'no') . "\n";

echo "\n=== ReflectionClass on FQN + namespace info ===\n";
$rc = new \ReflectionClass('\\App\\Models\\User');
echo "name: " . $rc->getName() . "\n";
echo "ns: " . $rc->getNamespaceName() . "\n";
echo "short: " . $rc->getShortName() . "\n";

echo "\ndone\n";
