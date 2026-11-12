<?php
// http_build_query over arrays and objects: nesting, prefixes, separators,
// what is skipped, and what the calling scope can see

class Item {
    public $name = 'widget';
    protected $secret = 'hidden';
    private $internal = 'x';
    public $tags = ['a', 'b'];
    public $none = null;
    function query() { return http_build_query($this); }
}

enum Suit: string { case Hearts = 'H'; case Spades = 'S'; }
enum Plain { case One; }

var_dump(http_build_query(['a' => 1, 'b' => 'two words', 'c' => true, 'd' => false, 'e' => 1.5, 'f' => null]));
var_dump(http_build_query([1, 2, 'k' => 3], 'n_'));
var_dump(http_build_query(['x' => ['y' => ['z' => 1]], 'list' => [10, 20]]));
var_dump(http_build_query(['a b' => 'c d', 'e~' => 'f~'], '', '&amp;', PHP_QUERY_RFC3986));
var_dump(http_build_query(['a' => 1, 'b' => 2], '', ';'));
var_dump(http_build_query(new Item));
var_dump((new Item)->query());
var_dump(http_build_query(['item' => new Item]));
var_dump(http_build_query(['s' => Suit::Hearts, 'list' => [Suit::Spades]]));
var_dump(http_build_query(['f' => fopen('php://memory', 'r'), 'g' => 1]));
var_dump(http_build_query([]));
try {
    http_build_query(['p' => Plain::One]);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    http_build_query(Suit::Hearts);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
$o = new stdClass;
$o->a = 1;
$o->nested = new stdClass;
$o->nested->b = 'c';
var_dump(http_build_query($o));
