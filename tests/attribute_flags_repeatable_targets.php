<?php
#[Attribute(Attribute::TARGET_CLASS | Attribute::IS_REPEATABLE)]
class Filter { public function __construct(public string $name) {} }

#[Attribute(Attribute::TARGET_METHOD | Attribute::TARGET_FUNCTION)]
class Route { public function __construct(public string $path, public string $method = "GET") {} }

#[Attribute(Attribute::TARGET_PROPERTY)]
class Column { public function __construct(public string $name) {} }

#[Filter("a")]
#[Filter("b")]
#[Filter("c")]
class X {
    #[Column("col_id")]
    public int $id;

    #[Route("/x", "POST")]
    public function go(): void {}
}

$rc = new ReflectionClass(X::class);
$filters = $rc->getAttributes(Filter::class);
foreach ($filters as $a) {
    $f = $a->newInstance();
    echo $f->name, " ";
}
echo "\n";
echo count($filters), "\n";

$col = $rc->getProperty("id")->getAttributes(Column::class)[0];
echo $col->newInstance()->name, "\n";

$route = $rc->getMethod("go")->getAttributes(Route::class)[0];
$r = $route->newInstance();
echo $r->path, " ", $r->method, "\n";

#[Attribute(Attribute::TARGET_ALL)]
class Anywhere { public function __construct(public string $tag) {} }

#[Anywhere("any-tag")]
class Y {}

$ry = new ReflectionClass(Y::class);
echo $ry->getAttributes()[0]->newInstance()->tag, "\n";

#[Attribute(Attribute::TARGET_CLASS)]
class JustClass { public function __construct() {} }

class HasBad {
    #[JustClass]
    public int $bad;
}

try {
    $p = new ReflectionClass(HasBad::class);
    $p->getProperty("bad")->getAttributes()[0]->newInstance();
    echo "no error\n";
} catch (Error $e) {
    echo "caught target\n";
}

#[Attribute(Attribute::TARGET_CLASS | Attribute::TARGET_PROPERTY | Attribute::TARGET_METHOD)]
class Multi { public function __construct(public string $where) {} }

#[Multi("on-class")]
class Z {
    #[Multi("on-prop")]
    public int $p;

    #[Multi("on-method")]
    public function m(): void {}
}

$rz = new ReflectionClass(Z::class);
echo $rz->getAttributes()[0]->newInstance()->where, "\n";
echo $rz->getProperty("p")->getAttributes()[0]->newInstance()->where, "\n";
echo $rz->getMethod("m")->getAttributes()[0]->newInstance()->where, "\n";
