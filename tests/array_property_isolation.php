<?php

// regression: array property defaults were shared between instances
// because initObjectProperties copied the pointer, not the array

class Bag {
    public array $items = [];
}

$a = new Bag();
$a->items[] = "apple";

$b = new Bag();
echo count($b->items) . "\n"; // 0, not 1
echo count($a->items) . "\n"; // 1

$b->items[] = "banana";
$b->items[] = "cherry";
echo count($a->items) . "\n"; // still 1
echo count($b->items) . "\n"; // 2

// also test with associative defaults
class Config {
    public array $settings = ["debug" => false];
}

$c1 = new Config();
$c1->settings["debug"] = true;

$c2 = new Config();
echo $c2->settings["debug"] ? "true" : "false";
echo "\n";
