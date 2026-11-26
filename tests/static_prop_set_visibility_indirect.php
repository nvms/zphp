<?php
// a compound assignment fetches a static property for writing before its
// operator runs, and a reference assignment fetches it indirectly: a
// private(set) property refuses both from outside its class

class C {
    public private(set) static int $count = 1;
    public private(set) static array $list = [];

    public static function bump(int $by) {
        self::$count += $by;
    }
}

function attempt(string $label, Closure $f) {
    try {
        $f();
        echo "$label: allowed\n";
    } catch (Throwable $e) {
        echo "$label: ", get_class($e), ': ', $e->getMessage(), "\n";
    }
}

attempt('assign', function () { C::$count = 5; });
attempt('compound', function () { C::$count += 2; });
attempt('compound with a bad operand', function () { C::$count += str_repeat('a', 3); });
attempt('concat', function () { C::$count .= '1'; });
attempt('coalesce', function () { C::$count ??= 3; });
attempt('reference to it', function () { $r = &C::$count; $r++; });
attempt('reference from it', function () { $x = 9; C::$count = &$x; });
attempt('array compound', function () { C::$list += [1]; });
var_dump(C::$count, C::$list);

// inside the class the same operations are allowed
attempt('inside', function () { C::bump(4); });
var_dump(C::$count);

// the right side runs before the refusal
attempt('order', function () { C::$count += (function () { echo "right side\n"; return 1; })(); });
