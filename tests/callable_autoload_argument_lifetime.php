<?php
// checking a callable argument may autoload its class, which runs php; the
// call's other arguments, a temporary callable array among them, must stay
// alive through it

class Base {
    static function useStack() {
        echo "OK ", func_num_args(), "\n";
    }
}

spl_autoload_register(function ($class) {
    eval('class Child extends Base {}');
    Child::useStack(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30);
});

call_user_func(array('Child', 'useStack'), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30);
var_dump(array_map(['Child', 'useStack'], [1]));
