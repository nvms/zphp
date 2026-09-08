<?php
function changeCharacter(string $value): string {
    $copy = $value;
    $value[0] = 'A';
    return $copy . ':' . $value;
}
var_dump(changeCharacter('word-' . 7));
$words = str_word_count(strtolower('ONE TWO ' . 'THREE'), 1);
$positions = str_word_count(strtoupper('one two ' . 'three'), 2);
gc_collect_cycles();
var_dump($words, $positions);
class NamedStringMethod {
    public static function getValue(): string { return 'ok'; }
}
$method = 'get' . 'Value';
var_dump(NamedStringMethod::$method());
$map = new WeakMap();
$key = new stdClass();
$map[$key] = 'temporary-' . 8;
unset($map[$key]);
var_dump(count($map));
function namedMirrorBatch(): string {
    for ($i = 0; $i < 10; ++$i) {
        $value = 'start-' . $i;
        $value .= '-end';
    }
    return $value;
}
var_dump(call_user_func('namedMirrorBatch'));
