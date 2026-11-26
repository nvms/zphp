<?php
// a method callback whose parameter is by reference, given a value by an
// internal function, warns as zend_call_function does
set_error_handler(function ($no, $msg) {
    echo "warning: $msg\n";
    return true;
});

class M {
    public function cb(&$a, &$b, $c) { $b = 1; return "cb"; }
    public static function s(&$a) { return "s"; }
    public function __invoke(&$x) { return "invoke"; }
}
class N extends M {}

$arr = [0, 0, 0];
var_dump(call_user_func_array([new M, 'cb'], $arr));
var_dump(call_user_func_array([new N, 'cb'], [1, 2, 3]));
var_dump(call_user_func_array('M::s', [1]));
var_dump(call_user_func_array([new N, 's'], [1]));
var_dump(call_user_func(new M, 5));
var_dump(call_user_func([new M, 'cb'], 1, 2, 3));
var_dump(array_map([new M, 's'], [1, 2]));

$v = 1;
var_dump(call_user_func_array([new M, 'cb'], [&$v, &$v, 3]));
var_dump($v);
