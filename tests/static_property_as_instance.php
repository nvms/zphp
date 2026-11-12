<?php
// naming a static property through an object notices, and the object gets
// a dynamic property of its own
class Counter {
    public static $count = 0;
    private static $secret = 's';
    public function peek() {
        return $this->secret;
    }
}
$c = new Counter;
var_dump($c->count);
$c->count = 5;
var_dump(Counter::$count);
var_dump($c->peek());
class Child extends Counter {
    private static $secret = 'child';
}
var_dump((new Child)->peek());
