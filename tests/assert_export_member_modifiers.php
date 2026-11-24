<?php
// assert() messages print final on class constants and properties, abstract
// on properties, and readonly on anonymous classes
$child = <<<'PHP'
<?php
function check(callable $f) {
    try {
        $f();
    } catch (AssertionError $e) {
        echo $e->getMessage(), "\n";
    }
}

check(fn() => assert(false && new class {
    final public const A = 1;
    final protected const int B = 2;
    public final const C = 3;
    const D = 4;
    final public $a;
    final public static $b;
    final public readonly int $c;
    public static final $f = 5;
    abstract public $d { get; }
    abstract protected private(set) int $e { set; }
    final public $g { get => 1; }
    final public function m() {}
    abstract public function n();
}));

check(fn() => assert(false && new readonly class {}));
check(fn() => assert(false && new #[A] readonly class(1) {}));
check(fn() => assert(false && new #[A] class(1) {}));
check(fn() => assert(false && new readonly class(2, 3) extends ArrayObject implements Countable {
    public int $x;
}));
PHP;

$file = tempnam(sys_get_temp_dir(), 'assert');
file_put_contents($file, $child);
echo shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d zend.assertions=1 ' . escapeshellarg($file) . ' 2>&1');
unlink($file);
