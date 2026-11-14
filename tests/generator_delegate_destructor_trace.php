<?php
// a destructor run while throw() stops a yield from, or while a delegate's
// exception unwinds into its parent, runs inside the generator's frame

function frames(Throwable $e): string
{
    $out = [];
    foreach ($e->getTrace() as $f) {
        $out[] = ($f['class'] ?? '') . ($f['type'] ?? '') . $f['function'] . (isset($f['line']) ? '@' . $f['line'] : '');
    }
    return implode(' < ', $out);
}

class Noisy
{
    public function __construct(public string $name) {}
    public function __destruct()
    {
        throw new Exception("dtor " . $this->name);
    }
}

function gen()
{
    yield from [1, 2, new Noisy("array")];
}

try {
    gen()->throw(new Exception("outer"));
} catch (Exception $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
    echo frames($e), "\n";
    $p = $e->getPrevious();
    echo $p ? $p->getMessage() : "none", "\n";
}

class It implements IteratorAggregate
{
    public function getIterator(): Generator
    {
        yield 'foo';
        throw new Exception("inner");
    }

    public function __destruct()
    {
        throw new Exception("it dtor");
    }
}

function f()
{
    yield from new It();
}

$g = f();
var_dump($g->current());
try {
    $g->next();
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
    echo frames($e), "\n";
    echo $e->getPrevious()?->getMessage(), "\n";
}

function quiet()
{
    try {
        yield from [1, new class {
            public function __destruct()
            {
                echo "destructed with ", count(debug_backtrace()), " frames\n";
            }
        }];
    } catch (Exception $e) {
        echo "caught ", $e->getMessage(), "\n";
        yield 99;
    }
}

$q = quiet();
var_dump($q->current());
var_dump($q->throw(new Exception("into quiet")));
echo "done\n";
