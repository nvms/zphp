<?php
// what php refuses when it links a class to its parent and interfaces: the
// internal interfaces' own rules, a static property's visibility narrowed,
// and a final method overridden (reported at the overriding method)
$cases = [
    'class A implements Iterator, IteratorAggregate {}',
    'abstract class B implements IteratorAggregate {} class A extends B implements Iterator {}',
    'class A implements Traversable {}',
    'abstract class A implements Traversable {} echo "abstract is fine\n";',
    'class A implements Throwable {}',
    'class A extends Exception implements Throwable {} echo "exception is fine\n";',
    'class A implements DateTimeInterface {}',
    'class A extends DateTime implements DateTimeInterface {} echo "subclass is fine\n";',
    'class A { public static $p; } class B extends A { private static $p; }',
    'class A { protected static $p; } class B extends A { private static $p; }',
    'class A { public static $p = 1; } class B extends A { public static $p = 2; } echo B::$p, "\n";',
    'class A { public $p; } class B extends A { protected $p; }',
    "class A { final function f() {} }\nclass B extends A {\n\n    function f() {}\n}",
    'class A { private final function f() {} } class B extends A { function f() {} } echo "private final is fine\n";',
];
foreach ($cases as $code) {
    echo $code, "\n";
    $command = escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -d error_reporting=-1 -r ' . escapeshellarg($code) . ' 2>&1';
    echo trim(shell_exec($command)), "\n\n";
}
