<?php

// regression: abstract class + trait with properties caused segfault
// from iterator invalidation when copying trait methods into self.functions

trait HasName {
    public string $name = "";
    public function getName(): string {
        return $this->name;
    }
}

abstract class Base {
    abstract public function describe(): string;
}

class Child extends Base {
    use HasName;
    public function describe(): string {
        return "child:" . $this->getName();
    }
}

$c = new Child();
$c->name = "test";
echo $c->describe() . "\n";

// multiple trait properties + abstract parent with own properties
trait HasTags {
    public array $tags = [];
    public int $priority = 0;
    public function addTag(string $t): void { $this->tags[] = $t; }
}

abstract class Entity {
    public string $id = "";
    abstract public function type(): string;
}

class Item extends Entity {
    use HasName, HasTags;
    public function type(): string { return "item"; }
}

$item = new Item();
$item->id = "001";
$item->name = "widget";
$item->addTag("new");
echo $item->type() . ":" . $item->id . ":" . $item->getName() . ":" . count($item->tags) . "\n";

// second instance should be independent
$item2 = new Item();
echo count($item2->tags) . "\n";
