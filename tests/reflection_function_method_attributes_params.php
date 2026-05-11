<?php
function greet(string $name, int $age = 30, ?string $city = null): string {
    return "$name/$age/$city";
}

$rf = new ReflectionFunction("greet");
echo $rf->getName(), "\n";
echo $rf->getNumberOfParameters(), "\n";
echo $rf->getNumberOfRequiredParameters(), "\n";

$params = $rf->getParameters();
foreach ($params as $p) {
    echo $p->getName(), ":", $p->isOptional() ? "opt" : "req";
    if ($p->hasType()) echo "/", $p->getType()->getName();
    if ($p->isOptional() and $p->isDefaultValueAvailable()) echo "/=", var_export($p->getDefaultValue(), true);
    echo "\n";
}

$rt = $rf->getReturnType();
echo $rt !== null ? $rt->getName() : "?", "\n";

echo $rf->invoke("alice"), "\n";
echo $rf->invoke("bob", 25), "\n";
echo $rf->invoke("carol", 40, "NYC"), "\n";
echo $rf->invokeArgs(["dave", 35]), "\n";

#[Attribute]
class Route {
    public function __construct(public string $path, public string $method = "GET") {}
}

#[Attribute]
class Tag {
    public function __construct(public string $name) {}
}

class Controller {
    #[Route("/users")]
    #[Tag("public")]
    public function listUsers(): array { return []; }

    #[Route("/users", "POST")]
    public function createUser(string $name, int $age): int { return 1; }

    public function deleteUser(int $id): void {}
}

$rc = new ReflectionClass("Controller");
$method = $rc->getMethod("listUsers");
$attrs = $method->getAttributes();
echo count($attrs), "\n";
foreach ($attrs as $a) {
    echo $a->getName(), ":", implode(",", array_map(fn($x) => var_export($x, true), $a->getArguments())), "\n";
}

$method = $rc->getMethod("createUser");
$attrs = $method->getAttributes();
foreach ($attrs as $a) {
    echo $a->getName(), ":", implode(",", $a->getArguments()), "\n";
}

$method = $rc->getMethod("deleteUser");
$attrs = $method->getAttributes();
echo count($attrs), "\n";

$attrs = $rc->getMethod("listUsers")->getAttributes(Route::class);
foreach ($attrs as $a) {
    $r = $a->newInstance();
    echo $r->path, " ", $r->method, "\n";
}

class Foo {
    public function bar(string $name, int $count = 0, array $opts = ["a", "b"]): void {}
}

$rm = new ReflectionMethod("Foo", "bar");
foreach ($rm->getParameters() as $p) {
    echo $p->getName();
    if ($p->hasType()) echo " type:", $p->getType()->getName();
    if ($p->isOptional()) echo " opt";
    if ($p->isDefaultValueAvailable()) echo " def=", json_encode($p->getDefaultValue());
    echo "\n";
}

#[Attribute]
class Cacheable {
    public function __construct(public int $ttl) {}
}

#[Cacheable(3600)]
class WithClassAttr {
    public int $id = 1;
}

$rc = new ReflectionClass("WithClassAttr");
$attrs = $rc->getAttributes();
echo count($attrs), "\n";
$a = $attrs[0];
echo $a->getName(), "\n";
$i = $a->newInstance();
echo $i->ttl, "\n";

function nullable(?string $s, int|float $n, array $opts): void {}
$rf = new ReflectionFunction("nullable");
$params = $rf->getParameters();
echo $params[0]->getType()->getName(), " ", $params[0]->allowsNull() ? "y" : "n", "\n";

$type1 = $params[1]->getType();
if ($type1 instanceof ReflectionUnionType) {
    $names = [];
    foreach ($type1->getTypes() as $t) $names[] = $t->getName();
    sort($names);
    echo implode("|", $names), "\n";
}

class Box {
    public function get(string $key): mixed { return null; }
    public function set(string $key, mixed $val): void {}
}

$rm = new ReflectionMethod("Box", "get");
$rt = $rm->getReturnType();
echo $rt->getName(), "\n";

$rm = new ReflectionMethod("Box", "set");
echo $rm->getNumberOfParameters(), "\n";
foreach ($rm->getParameters() as $p) {
    echo $p->getName(), ":", $p->getType()?->getName() ?? "?", "\n";
}

function variadic(int $first, string ...$rest): array {
    return [$first, $rest];
}
$rf = new ReflectionFunction("variadic");
foreach ($rf->getParameters() as $p) {
    echo $p->getName(), " variadic=", $p->isVariadic() ? "y" : "n", "\n";
}

#[Attribute(Attribute::TARGET_PARAMETER)]
class Validate {
    public function __construct(public string $rule) {}
}

class User {
    public function __construct(
        #[Validate("required")] public string $name,
        #[Validate("email")] public string $email,
    ) {}
}

$rc = new ReflectionClass("User");
$ctor = $rc->getConstructor();
foreach ($ctor->getParameters() as $p) {
    $attrs = $p->getAttributes();
    echo $p->getName(), ":", count($attrs), "\n";
    foreach ($attrs as $a) {
        $v = $a->newInstance();
        echo "  ", $v->rule, "\n";
    }
}
