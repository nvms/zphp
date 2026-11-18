<?php
// a method's static variables are the same whichever way it is called:
// a static call made just before doesn't hand its name to the next frame

class K {
    public function r() {
        static $c = 0;
        return ++$c;
    }
    public static function s() {
        static $calls = 0;
        return 's' . ++$calls;
    }
}

function plain() {
    static $n = 0;
    return ++$n;
}

$k = new K;
echo $k->r(), K::s(), call_user_func([$k, 'r']), $k->r(), "\n";
echo $k::s(), call_user_func([$k, 'r']), plain(), call_user_func('plain'), "\n";
echo K::s(), call_user_func_array([$k, 'r'], []), (new ReflectionMethod('K', 'r'))->invoke($k), "\n";
var_dump((new ReflectionMethod('K', 'r'))->getStaticVariables());
