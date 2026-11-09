<?php
// positional arguments and * widths, as translated messages and table renderers use them

$messages = [
    'en' => 'The %1$s contains %2$d monkeys and %3$.1f%% bananas',
    'de' => 'Im %1$s sind %3$.1f%% Bananen und %2$d Affen',
    'yoda' => '%2$d monkeys the %1$s contains, %2$d!',
];
foreach ($messages as $lang => $format) {
    echo $lang, ': ', sprintf($format, 'tree', 12, 99.5), "\n";
}

// positional and sequential arguments mixed: sequential ones keep their own count
var_dump(sprintf('%2$s %s %s %1$s', 'a', 'b'));
var_dump(sprintf('%1$s-%1$\'#10s-%1$-10s|', 'x'));
var_dump(sprintf('%3$05d|%1$x|%2$X|%1$o|%1$b', 255, 255, 42));

// * takes the width or precision from the next argument
$columns = [['id', 4], ['name', 12], ['total', 9]];
foreach ($columns as [$label, $w]) {
    echo sprintf('[%*s]', $w, $label), sprintf('[%-*s]', $w, $label), "\n";
}
var_dump(sprintf('%.*f|%*.*f|%-*.*e', 3, M_PI, 10, 2, M_E, 12, 1, 12345.678));
var_dump(sprintf('%*d|%0*d|%*s', 6, 42, 6, -42, 0, 'zero width'));

// * can name its argument too
var_dump(sprintf('%1$*2$s|%1$-*2$s|%3$.*2$f', 'ab', 5, 1.23456789));
var_dump(sprintf('%2$*1$.*3$f', 12, 3.14159265, 4));

// .* with -1 asks %g/%G/%h/%H for the shortest round-trip digits
var_dump(sprintf('%.*g|%.*G|%.*h|%.*H', -1, 0.1 + 0.2, -1, 1e100, -1, 1 / 3, -1, 123456789012345678.0));
var_dump(sprintf('%.*g', -1, 1.0));

// a precision with %x/%o/%b/%X makes php print no digits at all
var_dump(sprintf('[%.2x][%5.1o][%-6.3b][%.0X]', 255, 8, 5, 255));

// %l is accepted and ignored
var_dump(sprintf('%ld %lu %lf', -3, 3, 1.5));

foreach ([
    ['%*s', ['5', 'x']],
    ['%*s', [-1, 'x']],
    ['%*s', [2147483648, 'x']],
    ['%.*f', [1.5, 2.0]],
    ['%.*f', [-2, 2.0]],
    ['%.*s', [-1, 'abc']],
    ['%.*d', [-1, 5]],
    ['%0$s', ['x']],
    ['%2147483648$s', ['x']],
    ['%1$*0$s', ['x']],
    ['%*3$s', ['x', 'y']],
    ['%3$s', ['x', 'y']],
    ['%1$s %3$s %2$s', ['x']],
] as [$format, $args]) {
    try {
        var_dump(sprintf($format, ...$args));
    } catch (\Throwable $e) {
        echo $format, ': ', get_class($e), ': ', $e->getMessage(), "\n";
    }
    try {
        var_dump(vsprintf($format, $args));
    } catch (\Throwable $e) {
        echo $format, ' (vsprintf): ', get_class($e), ': ', $e->getMessage(), "\n";
    }
}
