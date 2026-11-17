<?php
namespace A\B { class C { const X = 1; } function f() { return 2; } }
namespace {
use A\{B\C};
use A \ { B\C as D };
var_dump(C::X, D::X, \A\B\f(), A\B\C::X, namespace\strlen("ab"));
foreach (["Foo \\ Bar;", "Foo\\ Bar;", "\\ strlen('x');", "use A\\ B;", "echo '\\\\';", "\$x = \"a\\\\b\";"] as $code) {
    try {
        eval($code);
        echo "ok\n";
    } catch (ParseError $e) {
        echo $e->getMessage(), "\n";
    }
}
}
