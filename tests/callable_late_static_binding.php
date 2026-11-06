<?php
// static:: inside a static method reached through a subclass callable names
// the subclass
class P { static function who() { return static::class; } function inst() { return static::class . " " . get_class($this); } }
class C extends P {}
var_dump(call_user_func(['C', 'who']), call_user_func('C::who'), call_user_func([new C, 'who']), call_user_func([new C, 'inst']));
$f = ['C', 'who']; var_dump($f());
$f = 'C::who'; var_dump($f());
var_dump(array_map(['C', 'who'], [1]));
