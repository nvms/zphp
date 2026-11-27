<?php
// an error handler throwing for an inheritance deprecation leaves the class
// declared; its exception is thrown once the declaration is done
set_error_handler(function($code, $message) {
    echo "handler: $message\n";
    throw new Exception($message);
});

try {
    class C extends DateTime {
        public function getTimezone() {}
        public function getTimestamp() {}
    };
} catch (Exception $e) {
    printf("%s: %s\n", $e::class, $e->getMessage());
}
var_dump(class_exists('C', false));
var_dump(new C() instanceof DateTime);

try {
    if (true) {
        class D extends ArrayIterator {
            public function current() {}
            public function key() {}
        }
    }
} catch (Exception $e) {
    printf("%s: %s\n", $e::class, $e->getMessage());
}
var_dump(class_exists('D', false));
