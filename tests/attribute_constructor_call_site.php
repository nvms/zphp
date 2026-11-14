<?php
// ReflectionAttribute::newInstance() runs the constructor as if it were
// called where the attribute is written: traces, argument errors and the
// writing file's strict_types all name that place

#[Attribute]
class Tag
{
    public function __construct(public int $n = 0, public ?string $label = null)
    {
        $here = debug_backtrace();
        echo "called from line ", $here[0]['line'], " of ", basename($here[0]['file']), "\n";
        echo "then ", $here[1]['class'], $here[1]['type'], $here[1]['function'], ", object ", get_class($here[1]['object']), "\n";
        $e = new Exception;
        echo "trace line ", $e->getTrace()[0]['line'], "\n";
    }
}

#[Attribute]
class Needs
{
    public function __construct(string $name, int $count) {}
}

#[Tag(3)]
class A {}

#[Needs]
class B {}

#[Needs([], 1)]
class C {}

#[Tag("5")]
class D {}

function show(string $class): void
{
    try {
        $attr = (new ReflectionClass($class))->getAttributes()[0]->newInstance();
        echo get_class($attr), " made\n";
    } catch (Throwable $e) {
        echo get_class($e), ": ", str_replace(__FILE__, 'FILE', $e->getMessage()), "\n";
        echo "  at line ", $e->getTrace()[0]['line'] ?? 'none', "\n";
    }
}

show(A::class);
show(B::class);
show(C::class);
show(D::class);

class M
{
    #[Tag(n: 7)]
    public function m() {}
}
(new ReflectionMethod(M::class, 'm'))->getAttributes()[0]->newInstance();

#[Tag(8)]
function f() {}
(new ReflectionFunction('f'))->getAttributes()[0]->newInstance();

$file = tempnam(sys_get_temp_dir(), 'acs');
file_put_contents($file, "<?php\ndeclare(strict_types=1);\n\n#[Tag(\"9\")]\nclass E {}\n");
require $file;
try {
    (new ReflectionClass(E::class))->getAttributes()[0]->newInstance();
} catch (TypeError $e) {
    echo "strict: ", str_replace([$file, str_replace('/', DIRECTORY_SEPARATOR, $file)], 'INCLUDED', $e->getMessage()), "\n";
}
unlink($file);
