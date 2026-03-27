<?php

class Foo {
    private string $name = "foo";
    public function getName(): string { return $this->name; }
}

class Bar {
    private string $name = "bar";
    public function getName(): string { return $this->name; }
}

// Closure::bind - rebind $this
$closure = function() {
    return $this->getName();
};

$foo = new Foo();
$bar = new Bar();

$boundToFoo = Closure::bind($closure, $foo);
$boundToBar = Closure::bind($closure, $bar);

echo $boundToFoo() . "\n";
echo $boundToBar() . "\n";

// Closure::bindTo (instance method)
$boundToFoo2 = $closure->bindTo($foo);
echo $boundToFoo2() . "\n";

// Closure::call - bind and immediately invoke
echo $closure->call($foo) . "\n";
echo $closure->call($bar) . "\n";

// closure with captured variables - captures preserved after bind
$prefix = "hello";
$greet = function() use ($prefix) {
    return $prefix . " " . $this->getName();
};

$boundGreet = Closure::bind($greet, $foo);
echo $boundGreet() . "\n";

$boundGreet2 = $greet->bindTo($bar);
echo $boundGreet2() . "\n";

// closure with parameters
$format = function(string $template) {
    return str_replace('{name}', $this->getName(), $template);
};

$bound = Closure::bind($format, $foo);
echo $bound("Name: {name}") . "\n";

// call with extra args
echo $format->call($bar, "Name: {name}") . "\n";

// bind preserves original closure
$original = Closure::bind($closure, $foo);
$rebound = Closure::bind($closure, $bar);
echo $original() . "\n";
echo $rebound() . "\n";

// Closure::fromCallable with named function
function add(int $a, int $b): int { return $a + $b; }
$addFn = Closure::fromCallable('add');
echo $addFn(3, 4) . "\n";

// closure defined inside a method with public properties
class Widget {
    public string $label;
    public function __construct(string $label) {
        $this->label = $label;
    }
    public function getFormatter(): Closure {
        return function(string $prefix) {
            return $prefix . ": " . $this->label;
        };
    }
}

$widget = new Widget("button");
$fmt = $widget->getFormatter();
echo $fmt("Widget") . "\n";

// rebind the method-defined closure to a different widget
$other = new Widget("input");
$rebound = Closure::bind($fmt, $other);
echo $rebound("Widget") . "\n";
