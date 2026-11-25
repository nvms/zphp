<?php
// built from php 8.6.0's Zend/tests/partial_application/*.phpt, one
// namespace per test

namespace pfa\rebinding_001 {
    echo "# rebinding_001\n";
    class C {
        function f($a) { var_dump($this); }
        static function g($a) { var_dump(static::class); }
    }

    class SubClass extends C {}

    class Unrelated {}

    $c = new C;
    $f = $c->f(?);
    $g = $c->g(?);

    echo "# Can be rebound to \$this of the same class:\n";
    $f->bindTo(new C)(1);

    echo "# Can be rebound to \$this of a sub-class:\n";
    $f->bindTo(new SubClass)(1);

    echo "# Cannot be rebound to an unrelated class:\n";
    try {
        $f->bindTo(new Unrelated)(1);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    echo "# Cannot unbind \$this on instance method:\n";
    try {
        $f->bindTo(null)(1);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    echo "# Can unbind \$this on static method:\n";
    $g->bindTo(null)(1);
}

namespace pfa\rebinding_002 {
    echo "# rebinding_002\n";
    class C {
        function f($a) { var_dump(static::class); }
    }

    class SubClass extends C {}

    function g($a) { var_dump(__FUNCTION__); }

    $c = new C;
    $f = $c->f(?);
    $g = g(?);

    echo "# Can be rebound to the same scope:\n";
    $f->bindTo($c, C::class)(1);

    echo "# Method cannot be rebound to a different scope:\n";
    try {
        $f->bindTo($c, SubClass::class)(1);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    echo "# Function cannot be rebound to a different scope:\n";
    try {
        $g->bindTo($c, SubClass::class)(1);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}

namespace pfa\rebinding_003 {
    echo "# rebinding_003\n";
    class C {
        function getF() {
            return function ($a) { var_dump($this, $this === $a); };
        }
        function getG() {
            return static function ($a) { var_dump(static::class, $a); };
        }
    }

    class SubClass extends C {}

    class Unrelated {}

    $c = new C();
    $f = $c->getF()(?);
    $g = $c->getG()(?);

    echo "# Can be rebound to \$this of the same class:\n";
    $d = new C();
    $f->bindTo($d)($d);

    echo "# Can be rebound to \$this of a sub-class:\n";
    $d = new SubClass();
    $f->bindTo($d)($d);

    echo "# Cannot be rebound to an unrelated class:\n";
    try {
        $f->bindTo(new Unrelated)($c);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    echo "# Cannot unbind \$this on non-static closure:\n";
    try {
        $f->bindTo(null)($c);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    echo "# Can unbind \$this on static closure:\n";
    $g->bindTo(null)($c);
}

namespace pfa\static_pfa_001 {
    echo "# static_pfa_001\n";
    class C {
        public static function f($a) {
            var_dump($a);
        }
    }

    $f = C::f(?);
    echo new ReflectionFunction($f), "\n";
    $f(1);

    $f = (new C)->f(?);
    echo new ReflectionFunction($f), "\n";
    $f(1);

    // Warns
    var_dump($f->bindTo(new C));
}

namespace pfa\static_pfa_002 {
    echo "# static_pfa_002\n";
    class C {
        public function f($a) {
            var_dump($this, $this === $a);
        }
    }

    $c = new C();
    $f = $c->f(?);
    echo new ReflectionFunction($f), "\n";
    $f($c);

    $c2 = new C();
    $f->bindTo($c2)($c2);
}

namespace pfa\static_pfa_003 {
    echo "# static_pfa_003\n";
    function f($a) {
        var_dump($a);
    }

    $f = f(?);
    echo new ReflectionFunction($f), "\n";
    $f(1);

    // Warns
    var_dump($f->bindTo(new class {}));
}

namespace pfa\static_pfa_004 {
    echo "# static_pfa_004\n";
    $c = function ($a) {
        try {
            var_dump($this, $this === $a);
        } catch (Error $e) {
            echo $e::class, ": ", $e->getMessage(), "\n";
        }
    };

    echo "# Original PFA\n";

    $f = $c(?);
    echo new ReflectionFunction($f), "\n";
    $f($c);

    echo "# Re-bound PFA\n";

    $c2 = new class {};
    $f->bindTo($c2)($c2);
}

namespace pfa\static_pfa_005 {
    echo "# static_pfa_005\n";
    $c = static function ($a) {
        var_dump($a);
    };

    $f = $c(?);
    echo new ReflectionFunction($f), "\n";
    $f(1);

    // Warns
    var_dump($f->bindTo(new class {}));
}

namespace pfa\magic_scope {
    echo "# magic_scope\n";
    class InstanceTarget
    {
        private function secret(string $value): void
        {
            echo "PRIVATE-INSTANCE:$value\n";
        }

        public function __call(string $name, array $arguments): void
        {
            echo "MAGIC-INSTANCE:$name:" . implode(',', $arguments) . "\n";
        }
    }

    class StaticTarget
    {
        private static function secret(string $value): void
        {
            echo "PRIVATE-STATIC:$value\n";
        }

        public static function __callStatic(string $name, array $arguments): void
        {
            echo "MAGIC-STATIC:$name:" . implode(',', $arguments) . "\n";
        }
    }

    $instance = new InstanceTarget();

    $instance->secret('direct');
    StaticTarget::secret('direct');

    $instancePartial = $instance->secret(?);
    $staticPartial = StaticTarget::secret(?);
    $instancePartial('controlled');
    $staticPartial('controlled');
}
