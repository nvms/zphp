<?php
// call_user_func_array() keeps the references of its argument array when
// the callable is a __call or __callStatic trampoline: the magic method's
// $args holds them, so a by-reference callee further on writes through

function inc(&$x) { $x++; }

class Proxy {
    public function __call($name, $args) {
        echo "$name called\n";
        call_user_func_array('inc', $args);
    }

    public static function __callStatic($name, $args) {
        echo "static $name called\n";
        $args[0] = 'replaced';
        $args[1] .= '!';
    }
}

$arg = 1;
$args = [&$arg];
$proxy = new Proxy;
call_user_func_array([$proxy, 'bar'], $args);
call_user_func_array([$proxy, 'bar'], [&$arg]);
var_dump($arg);

$a = 'first';
$b = 'second';
call_user_func_array(['Proxy', 'baz'], [&$a, &$b, 'value']);
var_dump($a, $b);

// values stay values
$c = 5;
call_user_func_array([$proxy, 'bar'], [$c]);
var_dump($c);

// a direct call passes values to the trampoline
$d = 1;
$proxy->bar($d);
var_dump($d);
