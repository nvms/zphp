<?php
// an internal function's arguments go when it returns: a destructor that
// throws there stops the code after the call, which never sees the result
class D extends ArrayIterator {
    function __destruct() {
        throw new Exception("from destructor");
    }
}

class T {
    static $tries = 0;
    static function test($func) {
        while (self::$tries < 3) {
            try {
                self::$tries++;
                var_dump($func(new D([1])));
                break;
            } catch (Exception $e) {
                echo $e->getMessage(), "\n";
            }
        }
    }
}
T::test('iterator_to_array');

try {
    var_dump(iterator_count(new D([2])));
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
echo "end\n";
