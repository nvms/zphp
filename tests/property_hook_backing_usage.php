<?php
// a hooked property has backing storage only when one of its own hook bodies
// names $this->prop directly; closures, arrow functions and anonymous
// classes inside the hook don't count

class Test {
    public $direct { get => $this->direct; }
    public $arrow { get => fn () => $this->arrow; }
    public $closure { get => function () { return $this->closure; }; }
    public $other { get => $this->direct; }
    public $nothing { get {} }
    public $nested { get { var_dump($this->nested); } }
    public $anon { get => new class { function test() { $this->anon; } }; }
    public $nullsafe { get => $this?->nullsafe; }
}

foreach ((new ReflectionClass(Test::class))->getProperties() as $prop) {
    echo $prop->getName(), ': ', $prop->isVirtual() ? 'virtual' : 'backed', "\n";
}
var_dump(new Test());
