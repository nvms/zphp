<?php
// php 8.6's assert() messages keep the parentheses that change meaning
// (`(NAME)::m()`, `($o->f)()`), quote variable names that aren't valid
// identifiers, and print every interpolated expression in braces. a name in
// parentheses before `::` is a constant, also when the code runs

function run(string $code): void
{
    $file = tempnam(sys_get_temp_dir(), 'assert');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d zend.assertions=1 -d display_errors=1 -d log_errors=0 -d error_reporting=-1 ' . escapeshellarg($file) . ' 2>&1');
    echo str_replace($file, 'FILE', $out);
    unlink($file);
}

run(<<<'PHP'
class Foo {
    public static $p = true;
    public const C = true;
    public static Closure $sf;
    public Closure $f;
    public static function m() { return true; }
    public function __get($n) { return $n; }
    public function run() {
        $this->f = strrev(...);
        self::$sf = strrev(...);
        foreach ([
            fn() => assert(($this->f)('abc') !== 'cba'),
            fn() => assert(($this?->f)('abc') !== 'cba'),
            fn() => assert((self::$sf)('abc') !== 'cba'),
        ] as $f) {
            try { $f(); } catch (AssertionError $e) { echo $e->getMessage(), "\n"; }
        }
    }
}
const bar = 'Foo';
const baz = new stdClass();
$foo = new Foo();
var_dump((bar)::m(), (bar)::$p, (bar)::C, (baz)::class, new (bar)() instanceof (bar));
$checks = [
    fn() => assert(!$foo instanceof (bar)),
    fn() => assert(!new (bar)()),
    fn() => assert(!(bar)::m()),
    fn() => assert(!(bar)::$p),
    fn() => assert(!(bar)::C),
    fn() => assert((baz)::class !== 'stdClass'),
    fn() => assert(!${'---'} . ${'it\'s'}),
    fn() => assert(!$foo->{'---'}),
    fn() => assert(!"$foo->x and {$foo->y} ${a} $b[1] {$c}[]"),
];
foreach ($checks as $f) {
    try { $f(); } catch (AssertionError $e) { echo $e->getMessage(), "\n"; }
}
(new Foo)->run();
PHP);
