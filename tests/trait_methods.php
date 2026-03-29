<?php

trait Greetable {
    public function greet(): string {
        return "Hello, " . $this->name();
    }
}

trait Nameable {
    public function name(): string {
        return $this->label;
    }
}

class Person {
    use Greetable, Nameable;

    public string $label;

    public function __construct(string $label) {
        $this->label = $label;
    }
}

$p = new Person("Alice");
echo $p->greet() . "\n";
echo $p->name() . "\n";

// trait method calling another trait method on the same object
trait HasEvents {
    protected array $events = [];

    public function on(string $event, callable $fn): void {
        $this->events[$event] = $fn;
    }

    public function fire(string $event): void {
        if (isset($this->events[$event])) {
            ($this->events[$event])();
        }
    }
}

trait HasName {
    protected string $itemName = '';

    public function setName(string $n): static {
        $this->itemName = $n;
        return $this;
    }

    public function getName(): string {
        return $this->itemName;
    }
}

class Widget {
    use HasEvents, HasName;
}

$w = new Widget();
$w->setName("btn");
echo $w->getName() . "\n";

$fired = false;
$w->on("click", function() use (&$fired) {
    $fired = true;
});
$w->fire("click");
echo $fired ? "fired" : "not fired";
echo "\n";
