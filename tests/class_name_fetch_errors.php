<?php
// Name::class: relative names that resolve to nothing throw, ::class on a
// value needs an object, and constant expressions can't use static::class or
// a parent the class doesn't have

namespace App {
    class Base {}
    class Kid extends Base {
        const K = parent::CLASS;
        function d($x = parent::class, $y = self::Class) { return [$x, $y]; }
        static function s() { return [self::class, static::class, parent::class]; }
    }
    class Grand extends Kid {}
    trait T {
        function p() { return parent::class; }
    }
    class NoParent { use T; }
    var_dump(Kid::K, (new Kid)->d(), Grand::s(), \Moo::CLASS);
    try {
        (new NoParent)->p();
    } catch (\Error $e) {
        echo $e->getMessage(), "\n";
    }
}

namespace {
    foreach (['self::class', 'parent::class', 'static::class', '[self::class]', '(function () { return self::class; })()'] as $code) {
        try {
            var_dump(eval("return $code;"));
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
    }
    function f($v) {
        return $v::class;
    }
    foreach ([new stdClass, null, 1, 'stdClass', [1]] as $v) {
        try {
            var_dump(f($v));
        } catch (TypeError $e) {
            echo $e->getMessage(), "\n";
        }
    }
    $cases = [
        '(1+1)::class;', '(2)::class;', '("a" . "b")::class;', '(-1.5)::class;', '(true)::class;',
        'class A { const X = static::class; }', 'class A { function f($a = static::class) {} }',
        'class A { const X = parent::class; }', 'class A { const X = [1, parent::Y]; }',
        'class P {} class A extends P { const X = parent::class; } echo A::X;',
        'trait T { const X = parent::class; } echo "ok";',
    ];
    foreach ($cases as $code) {
        $file = tempnam(sys_get_temp_dir(), 'cnf');
        file_put_contents($file, "<?php\n$code\n");
        $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 ' . escapeshellarg($file) . ' 2>&1');
        echo $code, ' => ', trim(str_replace($file, 'FILE', $out)), "\n";
        unlink($file);
    }
}
