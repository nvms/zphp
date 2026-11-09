<?php
// the errors the printf family throws, and what it does with odd arguments

class Money
{
    public function __construct(private int $cents) {}
    public function __toString(): string { return sprintf('$%d.%02d', intdiv($this->cents, 100), $this->cents % 100); }
}
class Plain {}
class Loud
{
    public function __toString(): string { throw new RuntimeException('cannot render'); }
}

function attempt(string $label, callable $fn): void
{
    try {
        var_dump($fn());
    } catch (\Throwable $e) {
        echo $label, ': ', get_class($e), ': ', $e->getMessage();
        for ($p = $e->getPrevious(); $p; $p = $p->getPrevious()) {
            echo ' (previous ', get_class($p), ': ', $p->getMessage(), ')';
        }
        echo "\n";
    }
}

$format = 'Total: %s for %d items%';
attempt('trailing %', fn() => sprintf($format, new Money(1999), 3));
$format = 'Rate: %y';
attempt('unknown specifier', fn() => sprintf($format, 5));
$format = "%'";
attempt('padding at the end', fn() => sprintf($format, 5));
$format = '%5';
attempt('width at the end', fn() => sprintf($format, 5));
$format = '%s and %s';
attempt('too few', fn() => sprintf($format, 'one'));
attempt('too few, vsprintf', fn() => vsprintf($format, ['one']));
attempt('too few, printf', fn() => printf($format, 'one'));
attempt('too few, fprintf', fn() => fprintf(STDOUT, $format, 'one'));
attempt('too few, vfprintf', fn() => vfprintf(STDOUT, $format, ['one']));
attempt('no args, missing spec', fn() => sprintf('%'));
attempt('width overflow', fn() => sprintf('%2147483648d', 1));
attempt('precision overflow', fn() => sprintf('%.2147483648f', 1));
attempt('unknown with no args', fn() => sprintf('%y'));

// parameter types
attempt('format array', fn() => sprintf([], 1));
attempt('format object', fn() => sprintf(new Plain()));
attempt('format stringable', fn() => sprintf(new Money(250)));
attempt('format int', fn() => sprintf(12345));
attempt('format float', fn() => sprintf(1.5));
attempt('vsprintf values int', fn() => vsprintf('%d', 5));
attempt('vprintf values string', fn() => vprintf('%d', '5'));
attempt('vprintf values null', fn() => vprintf('%d', null));
attempt('fprintf stream string', fn() => fprintf('php://stdout', '%d', 1));
attempt('vfprintf stream string', fn() => vfprintf('php://stdout', '%d', [1]));
attempt('vfprintf values', fn() => vfprintf(STDOUT, '%d', 1));
$closed = fopen('php://memory', 'w');
fclose($closed);
attempt('fprintf closed stream', fn() => fprintf($closed, '%d', 1));

// argument conversions
$values = [null, true, false, 0, -7, 3.99, -3.99, '42abc', ' 12', "\t\n9", 'abc', '1e3', '0x1A', [], [1, 2], new Money(5)];
foreach ($values as $v) {
    echo json_encode(is_object($v) ? 'Money' : $v), ' => ', sprintf('[%s] [%d] [%u] [%.2f] [%x] [%c] [%e]', $v, $v, $v, $v, $v, is_array($v) || is_object($v) ? 65 : $v, $v), "\n";
}
attempt('plain object as string', fn() => sprintf('[%s|%s]', new Plain(), 'ok'));
attempt('plain object as int', fn() => sprintf('[%d|%f|%x]', new Plain(), new Plain(), new Plain()));
attempt('throwing __toString', fn() => sprintf('[%s|%s|%5.1f]', new Loud(), new Money(100), 2.5));
attempt('throwing then a bad specifier', fn() => sprintf('[%s|%y]', new Loud(), 1));
attempt('plain object then too few', fn() => sprintf('[%s|%s|%s]', new Plain(), 1));
attempt('float out of int range', fn() => sprintf('[%d|%x|%u]', 1e20, -1e19, INF));
$nan = acos(8);
attempt('nan as string', fn() => sprintf('[%s|%d]', $nan, $nan));

// a handler that throws turns the warning into the exception, and formatting goes on
set_error_handler(function (int $no, string $msg): bool {
    throw new ErrorException($msg, 0, $no);
});
attempt('handler throws', fn() => sprintf('[%s|%s|%d]', [], new Money(1), new Plain()));
attempt('handler throws, printf still prints', fn() => printf("[%s|%s]\n", [], 'after'));
restore_error_handler();

// printf and friends return the number of bytes
$n = printf("%s has %d bytes\n", 'this line', 23);
var_dump($n);
$n = vprintf("%2\$s %1\$s\n", ['world', 'hello']);
var_dump($n);
$fp = fopen('php://memory', 'w+');
var_dump(fprintf($fp, '%05.1f|%-6s|', 3.14159, 'ab'), vfprintf($fp, '%b-%o', [5, 8]));
rewind($fp);
var_dump(stream_get_contents($fp));
