<?php
// regression: enum static methods (cases / from / tryFrom) dispatched
// indirectly - via call_user_func, an array callable, or first-class callable
// syntax - now resolve correctly. callByName built the NativeContext with a
// null call_name, but enumCases/enumFrom/enumTryFrom read the 'Class::method'
// prefix off call_name to know which enum they belong to, so every indirect
// dispatch hit 'unknown runtime error'
enum Suit: string {
    case Hearts = 'H';
    case Diamonds = 'D';
    case Clubs = 'C';
    case Spades = 'S';
}

// call_user_func with 'Class::method' string
echo count(call_user_func('Suit::cases')) . "\n";

// call_user_func with [class, method] array
echo count(call_user_func(['Suit', 'cases'])) . "\n";

// plain array-callable invocation
$cb = ['Suit', 'cases'];
echo count($cb()) . "\n";

// first-class callable syntax
$cases = Suit::cases(...);
echo count($cases()) . "\n";

// from / tryFrom indirectly
echo call_user_func('Suit::from', 'H')->name . "\n";
$tf = Suit::tryFrom(...);
var_dump($tf('X'));
echo call_user_func(['Suit', 'from'], 'S')->name . "\n";

// array_map with the first-class callable
$names = array_map(fn($c) => $c->value, call_user_func('Suit::cases'));
print_r($names);
