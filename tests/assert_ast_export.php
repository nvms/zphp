<?php
// assert() reports its assertion printed back as php source (zend_ast_export)
// when no description is given, and runs only while zend.assertions is 1

function run(string $code, string $ini = 'zend.assertions=1'): void
{
    $file = tempnam(sys_get_temp_dir(), 'assert');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d ' . $ini . ' -d display_errors=1 -d log_errors=0 -d error_reporting=-1 ' . escapeshellarg($file) . ' 2>&1');
    echo str_replace($file, 'FILE', $out);
    unlink($file);
}

$cases = [
    'false && -1 && 1.0 && 0x10 && 1e100 && 0.1 && TRUE && \null && __LINE__',
    '(int)$a && (float)$c && (bool)$d && (string)$e && (array)$f && (object)$g',
    '"a$b c" && "x {$y->z} {$a[1]} $a[k] $o->p" && \'it\\\'s\' && "tab\there"',
    '$a <> $b && $a and $b || !$x instanceof Foo && $c xor $d',
    'list($a, , $b) = $c && [$d, [$e]] = $f && [\'k\' => $v, \'j\' => &$w] = $g',
    '($a = &$b) && $c ??= 1 && $d **= 2 && $e .= "x" && $f ?? $g ?: $h',
    '$a ? $b : ($c ? $d : $e) && (1 + 2) * 3 - -4 && 2 ** -1 && ($x . $y) + 1',
    'clone $x && new Foo && new \Bar\Baz(1, ...$args) && new namespace\Q() && new $cls($a)',
    'fn($x) => $x && (fn() => 1)() && static fn&(int ...$x): ?int => 1',
    'function &(array &$a, ?X $b = null, int|float $c = 1) use ($d, &$e): ?X { return $a; }',
    'print 1 && `ls $dir` && $a?->b && $a?->c() && $a::class && A::class && A::B && A::$c',
    '$$a && ${"a"} && $a->{"b"} && $a->$b && $a->{$b . "c"}() && A::$b() && $a[] = 1',
    '0 && strlen(...) && $o->m(...) && A::m(...) && $f(1, ...$g) && f(a: 1, b: $c)',
    'match ($x) { 1, 2 => "a", default => "b" } && isset($a, $b[1]) && empty($c) && eval("1")',
    '0 && include "f.php" && require_once $f && exit && die(1) && function () { yield; $x = yield 1 => 2; yield from $g; }',
    '1 |> strlen(...) && $a++ && --$b && @f() && ~$c && +$d',
];
$code = "function cases() {\n";
foreach ($cases as $case) {
    $code .= "try { assert($case); } catch (Throwable \$e) { echo get_class(\$e), \": \", \$e->getMessage(), \"\\n\"; }\n";
}
run($code . "}\ncases();\n");

// a block body prints statements one per line
run(<<<'PHP'
try {
    assert(0 && function () {
        global $a, $b;
        static $c, $d = 1;
        unset($e, $f);
        echo 1, 2;
        if ($a) {
            return 1;
        } elseif ($b) {
            return 2;
        } else if ($c) {
            return;
        } else {
            for ($i = 0, $j = 1; $i < $j; $i++) {
                continue;
            }
        }
        foreach ($a as $k => &$v) {
            break;
        }
        while ($a) {
        }
        do {
            $a--;
        } while ($a > 0);
        switch ($a) {
            case 1:
            case 2:
                echo 'x';
                break;
            default:
                echo 'y';
        }
        try {
            throw new E();
        } catch (A|B $e) {
        } catch (C) {
        } finally {
            $done = true;
        }
    });
} catch (AssertionError $e) {
    echo $e->getMessage(), "\n";
}
PHP);

// a description is used as given, a named assertion gets a named one
run(<<<'PHP'
try { assert(false, "custom"); } catch (AssertionError $e) { echo $e->getMessage(), "\n"; }
try { assert(assertion: 1 > 2); } catch (AssertionError $e) { echo $e->getMessage(), "\n"; }
try { assert(description: "only"); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { assert(false, new RuntimeException("thrown")); } catch (RuntimeException $e) { echo $e->getMessage(), "\n"; }
PHP);
run(<<<'PHP'
namespace Foo;
try { \assert(1 == 2); } catch (\AssertionError $e) { echo $e->getMessage(), "\n"; }
try { assert(1 == 2); } catch (\AssertionError $e) { echo $e->getMessage(), "\n"; }
PHP);

// zend.assertions=0 skips the call and its arguments, and -1 can't be
// switched at run time
run(<<<'PHP'
function side() { echo "evaluated\n"; return false; }
var_dump(assert(side()));
ini_set('zend.assertions', 1);
try { assert(side()); } catch (AssertionError $e) { echo $e->getMessage(), "\n"; }
var_dump(ini_set('zend.assertions', -1));
PHP, 'zend.assertions=0');
run(<<<'PHP'
var_dump(assert(false));
var_dump(ini_set('zend.assertions', 1));
PHP, 'zend.assertions=-1');

// with exceptions off, a failed assertion warns and returns false
run(<<<'PHP'
var_dump(@assert_options(ASSERT_EXCEPTION, 0));
var_dump(assert(false));
var_dump(assert(false, "described"));
PHP);
