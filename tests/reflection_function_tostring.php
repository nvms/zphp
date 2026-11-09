<?php
// ReflectionFunction, ReflectionMethod and ReflectionParameter string forms:
// typed parameters with defaults, by-reference and variadic parameters,
// closures with bound variables, and functions php itself provides

namespace App\Util;

const DEFAULT_SEPARATOR = ', ';

/**
 * Joins the non-empty parts.
 */
function join_parts(array $parts, string $separator = DEFAULT_SEPARATOR, ?callable $filter = null): string
{
    return implode($separator, array_filter($parts, $filter));
}

function &registry(): array
{
    static $items = [];
    return $items;
}

function clamp(int|float $value, int|float $min = 0, int|float $max = \PHP_INT_MAX): int|float
{
    return max($min, min($max, $value));
}

function collect(string $label, int &$count, mixed ...$values): void
{
    $count += count($values);
}

function nothing() {}

function settings(array $options = ['debug' => false, 'level' => 3, 'tags' => ['a', 'b']], float $ratio = 0.25, bool $strict = true, string $name = "it's \"quoted\"\n"): array
{
    return $options;
}

class Formatter
{
    const WIDTH = 80;

    public function __construct(private int $width = self::WIDTH, protected string $pad = ' ') {}

    public function format(string $text, int $indent = 0, ?string $prefix = null): string
    {
        return str_repeat($this->pad, $indent) . $prefix . $text;
    }

    public static function create(int ...$widths): static
    {
        return new static($widths[0] ?? self::WIDTH);
    }

    final protected function measure(string $text): int { return strlen($text); }
}

class UpperFormatter extends Formatter
{
    public function format(string $text, int $indent = 0, ?string $prefix = null): string
    {
        return strtoupper(parent::format($text, $indent, $prefix));
    }
}

echo new \ReflectionFunction('App\Util\join_parts');
echo new \ReflectionFunction('App\Util\registry');
echo new \ReflectionFunction('App\Util\clamp');
echo new \ReflectionFunction('App\Util\collect');
echo new \ReflectionFunction('App\Util\nothing');
echo new \ReflectionFunction('App\Util\settings');

echo new \ReflectionMethod(Formatter::class, '__construct');
echo new \ReflectionMethod(Formatter::class, 'format');
echo new \ReflectionMethod(Formatter::class, 'create');
echo new \ReflectionMethod(Formatter::class, 'measure');
echo new \ReflectionMethod(UpperFormatter::class, 'format');
echo new \ReflectionMethod(UpperFormatter::class, 'create');

$prefix = '> ';
$count = 0;
$closure = function (string $line, bool $trim = true) use ($prefix, &$count): string {
    static $calls = 0;
    $calls++;
    return $prefix . ($trim ? trim($line) : $line);
};
echo new \ReflectionFunction($closure);

$arrow = fn(int $n = 2) => $n * $count;
echo new \ReflectionFunction($arrow);

$bare = static function () {};
echo new \ReflectionFunction($bare);

foreach ((new \ReflectionFunction('App\Util\settings'))->getParameters() as $param) {
    echo $param, "\n";
}
echo new \ReflectionParameter([Formatter::class, 'format'], 'prefix'), "\n";
echo new \ReflectionParameter('App\Util\collect', 1), "\n";

// functions php provides
echo new \ReflectionFunction('str_pad');
echo new \ReflectionFunction('array_map');
echo new \ReflectionFunction('json_encode');
echo new \ReflectionFunction('strlen');
echo new \ReflectionMethod('ArrayObject', 'count');
echo new \ReflectionMethod('Exception', 'getMessage');
echo new \ReflectionFunction(strlen(...));
echo new \ReflectionParameter('str_pad', 3), "\n";
