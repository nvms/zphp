<?php
// a hook redeclared in a subclass is checked against the parent's hook of
// the same kind as a method, before the property's type

function declare_classes(string $code) {
    $file = tempnam(sys_get_temp_dir(), 'hook');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($file) . ' 2>&1');
    unlink($file);
    echo preg_replace('/ in \S+ on line \d+/', ' in FILE on line N', trim($out)), "\n";
}

declare_classes('class A { public $prop { final get { return 42; } } }
class B extends A { public $prop { get { return 24; } } }');

declare_classes('class A { public int $a { get { return 1; } } }
class B extends A { public int|float $a { get { return 1; } } }');

declare_classes('class A { public int|float $a { set {} } }
class B extends A { public int $a { set {} } }');

declare_classes('interface X {} interface Y extends X {}
class A { public Y $prop { set(X $prop) {} } }
class B extends A { public Y $prop { set(Y $prop) {} } }');

declare_classes('interface X {} interface Y extends X {}
class A { public Y $prop { set(Y $prop) {} } }
class B extends A { public Y $prop { set(X $prop) {} } }
echo "ok";');

declare_classes('class A { public $prop { get => 1; } }
class B extends A { public $prop { get => 2; set => null; } }
echo (new B)->prop;');
