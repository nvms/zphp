<?php
// an interface that fails to load after a variance check relied on the
// unlinked class is a fatal error, not an exception
class A {}
interface J {}

spl_autoload_register(function ($class) {
    echo "autoload $class\n";
    if ($class === "I") {
        class X {
            public function test(): J {}
        }
        class Y extends X {
            public function test(): B {}
        }
    }
});

try {
    class B extends A implements I, J {
    }
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
echo "unreachable\n";
