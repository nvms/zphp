<?php
class Base {
    protected function inherited() { return "inherited " . $this->name; }
}
class Alpha extends Base {
    public $message = "Valid representation";
    public function __construct(public string $name) {}
    public function bravo($suffix = '') { return $this->name . $suffix; }
    private function secret() { return "secret " . $this->name; }
    public static function make() { return static::class; }
    public function getSecret() { return Closure::fromCallable([$this, 'secret']); }
    public function message() { return $this->message; }
}
class Beta extends Alpha {}

$alpha = new Alpha("a");
foreach ([
    (new ReflectionMethod('Alpha', 'bravo'))->getClosure($alpha),
    $alpha->bravo(...),
    [$alpha, 'bravo'](...),
    Closure::fromCallable([$alpha, 'bravo']),
] as $closure) {
    $rf = new ReflectionFunction($closure);
    var_dump($rf->invoke('!'));
    var_dump($rf->invokeArgs(['suffix' => '?']));
    var_dump(get_class($rf->getClosureThis()));
}
var_dump((new ReflectionFunction($alpha->getSecret()))->invoke());
var_dump((new ReflectionFunction(Closure::bind(fn() => $this->inherited(...), $alpha, Alpha::class)()))->invoke());
var_dump((new ReflectionFunction(Beta::make(...)))->invoke());
var_dump((new ReflectionFunction((new ReflectionObject($alpha))->getMethod('message')->getClosure($alpha)))->invoke());
