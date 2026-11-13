<?php
// an error handler that throws from a callback's deprecation: a function
// whose parameters php parses (zpp) lets the exception go as it is.
// (call_user_func is php's ZEND_INIT_USER_CALL and wraps it in a TypeError
// whose message ends in "(null)"; php-src Zend/tests/gh_21699*.phpt, from
// php 8.5.5 on)

set_error_handler(function ($no, $msg) {
    throw new Exception($msg);
});

class Base {
    public static function __callStatic($name, $args) {}
}

class Child extends Base {
    public function test() {
        foreach (['array_map', 'usort', 'is_callable'] as $f) {
            try {
                $a = [2, 1];
                match ($f) {
                    'array_map' => array_map('self::y', $a),
                    'usort' => usort($a, 'parent::cmp'),
                    'is_callable' => is_callable('static::y'),
                };
                echo "$f: no exception\n";
            } catch (Throwable $e) {
                echo "$f: ", get_class($e), ": ", $e->getMessage(), "\n";
                var_dump($e->getPrevious());
            }
        }
    }
}

(new Child)->test();
