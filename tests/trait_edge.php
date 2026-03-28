<?php

// trait with constructor property
trait Configurable {
    private array $config = [];
    public function configure(string $key, mixed $value): void {
        $this->config[$key] = $value;
    }
    public function getConfig(string $key): mixed {
        return $this->config[$key] ?? null;
    }
}

class Service {
    use Configurable;
    public string $name;
    public function __construct(string $name) {
        $this->name = $name;
    }
}

$s = new Service("api");
$s->configure("timeout", 30);
echo $s->name . "\n"; // api
echo $s->getConfig("timeout") . "\n"; // 30
echo ($s->getConfig("missing") === null ? "null" : "nope") . "\n"; // null

// trait with abstract method
trait Renderable {
    abstract protected function renderContent(): string;
    public function render(): string {
        return "<div>" . $this->renderContent() . "</div>";
    }
}

class Button {
    use Renderable;
    protected function renderContent(): string {
        return "Click me";
    }
}

$b = new Button();
echo $b->render() . "\n"; // <div>Click me</div>

// as visibility change without alias
trait Greeting {
    protected function hello(): string { return "hello"; }
}

class Greeter {
    use Greeting { hello as public; }
}

$g = new Greeter();
echo $g->hello() . "\n"; // hello

// trait static methods
trait Counter {
    private static $count = 0;
    public static function increment(): void {
        self::$count++;
    }
    public static function getCount(): int {
        return (int)self::$count;
    }
}

class Tracker {
    use Counter;
}

Tracker::increment();
Tracker::increment();
echo Tracker::getCount() . "\n"; // 2

// multiple traits with properties
trait HasName {
    public string $name = "unnamed";
}

trait HasAge {
    public int $age = 0;
}

class Person {
    use HasName;
    use HasAge;
}

$p = new Person();
$p->name = "Alice";
$p->age = 30;
echo $p->name . " is " . $p->age . "\n"; // Alice is 30

// trait using another trait (nested traits)
trait Timestampable {
    public function getCreatedAt(): string { return "2024-01-01"; }
}

trait SoftDeletes {
    public function getDeletedAt(): string { return "null"; }
}

trait HasTimestamps {
    use Timestampable;
    use SoftDeletes;
    public function getTimestamps(): string {
        return $this->getCreatedAt() . "," . $this->getDeletedAt();
    }
}

class Model {
    use HasTimestamps;
}

$m = new Model();
echo $m->getTimestamps() . "\n"; // 2024-01-01,null
echo $m->getCreatedAt() . "\n"; // 2024-01-01
echo $m->getDeletedAt() . "\n"; // null

// three levels deep: trait -> trait -> trait
trait Base {
    public function baseMethod(): string { return "base"; }
}

trait Middle {
    use Base;
    public function middleMethod(): string { return $this->baseMethod() . "+middle"; }
}

trait Top {
    use Middle;
    public function topMethod(): string { return $this->middleMethod() . "+top"; }
}

class Deep {
    use Top;
}

$d = new Deep();
echo $d->topMethod() . "\n"; // base+middle+top
echo $d->middleMethod() . "\n"; // base+middle
echo $d->baseMethod() . "\n"; // base

// nested traits with properties
trait HasId {
    public int $id = 0;
}

trait HasLabel {
    public string $label = "";
}

trait Identifiable {
    use HasId;
    use HasLabel;
    public function identify(): string {
        return $this->id . ":" . $this->label;
    }
}

class Widget {
    use Identifiable;
}

$w = new Widget();
$w->id = 42;
$w->label = "button";
echo $w->identify() . "\n"; // 42:button

// class using both direct trait and nested trait
trait Loggable {
    public function log(string $msg): string { return "[LOG] " . $msg; }
}

class App {
    use Identifiable;
    use Loggable;
}

$a = new App();
$a->id = 1;
$a->label = "app";
echo $a->identify() . "\n"; // 1:app
echo $a->log("started") . "\n"; // [LOG] started
