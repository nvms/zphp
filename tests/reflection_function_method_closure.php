<?php
#[Attribute(Attribute::TARGET_FUNCTION)]
class F {}
#[Attribute(Attribute::TARGET_METHOD)]
class M {}
#[Attribute]
class Any { public function __construct(public string $tag = '') {} }

class Base {
    #[Any('base')]
    protected function inherited() { return "inherited " . $this->name; }
}

class Alpha extends Base {
    public function __construct(public string $name) {}
    #[F]
    #[M]
    #[Any('bravo')]
    public function bravo($suffix = '') { return $this->name . $suffix; }
    private function secret() { return "secret " . $this->name; }
    public static function make() { return static::class; }
    public function getSecret() { return Closure::fromCallable([$this, 'secret']); }
}
class Beta extends Alpha {}

$alpha = new Alpha("a");
$closures = [
    'getClosure' => (new ReflectionMethod('Alpha', 'bravo'))->getClosure($alpha),
    'first-class' => $alpha->bravo(...),
    'array first-class' => [$alpha, 'bravo'](...),
    'fromCallable' => Closure::fromCallable([$alpha, 'bravo']),
];
foreach ($closures as $label => $closure) {
    echo "-- $label\n";
    $rf = new ReflectionFunction($closure);
    var_dump($rf->invoke('!'));
    var_dump($rf->invokeArgs(['suffix' => '?']));
    foreach ($rf->getAttributes() as $attr) {
        echo $attr->getName(), " target ", $attr->getTarget(), "\n";
        try {
            var_dump($attr->newInstance());
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
    }
    var_dump(count($rf->getAttributes(Any::class)));
}

echo "-- private\n";
$rf = new ReflectionFunction($alpha->getSecret());
var_dump($rf->invoke());
echo "-- inherited\n";
$rf = new ReflectionFunction(Closure::bind(fn() => $this->inherited(...), $alpha, Alpha::class)());
var_dump($rf->invoke());
var_dump($rf->getAttributes()[0]->newInstance()->tag);
echo "-- static\n";
$rf = new ReflectionFunction(Beta::make(...));
var_dump($rf->invoke());
var_dump($rf->getAttributes());
echo "-- function\n";
#[F]
#[M]
function f() { return 'f'; }
$rf = new ReflectionFunction(f(...));
var_dump($rf->invoke());
foreach ($rf->getAttributes() as $attr) {
    try {
        var_dump($attr->newInstance());
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
