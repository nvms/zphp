<?php
// php folds a literal constant expression only when it raises nothing;
// one that warns or throws is evaluated on first use
set_error_handler(function ($no, $str, $file, $line) {
    echo "handler: $str (line $line)\n";
    return true;
});

class C {
    const X = "0foo" % 5;
    const OK = 1 << 3 | 1 << 4;
    const F = 1.5 | 2;
    public $p = "1x" + 1;
    public static $s = "2x" * 2;
}

echo "declared\n";
var_dump(C::OK);
var_dump(C::X);
var_dump(C::X);
var_dump(C::F);
echo "static\n";
var_dump(C::$s);
echo "new\n";
var_dump(new C);

class D1 { const V = 1 / 0; }
class D2 { const V = 7 % (3 - 3); }
class D3 { const V = 1 << -1; }
class D4 { const V = [1] + 1; }
class D5 { const V = "abc" * 2; }
class D7 { const V = 0 ** -1; }
echo "declared more\n";
foreach (['D1', 'D2', 'D3', 'D4', 'D5', 'D7'] as $class) {
    try {
        var_dump(constant("$class::V"));
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

set_error_handler(function () {
    throw new ErrorException("from handler");
});
class G {
    const X = "5 apples" + 1;
}
try {
    var_dump((new ReflectionClass('G'))->getConstants());
} catch (Throwable $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
