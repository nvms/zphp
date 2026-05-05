<?php
// covers: sprintf with %d, %s, %f, %e, %g, %b, %o, %x, %X, %c, %u, %%,
//   width and precision specifiers, left/right alignment, sign forcing,
//   custom padding chars, positional args (%1$s), zero padding, negative
//   numbers, very large/small floats, vsprintf, str_repeat

function row(string $fmt, ...$args): void {
    $out = sprintf($fmt, ...$args);
    echo sprintf("  %-30s -> [%s]\n", $fmt, $out);
}

echo "=== integer formats ===\n";
row('%d', 42);
row('%d', -42);
row('%d', 0);
row('%5d', 42);
row('%-5d|', 42);
row('%05d', 42);
row('%+d', 42);
row('%+d', -42);
row('%+5d', 7);
row('%-+5d|', 7);
row("%'A5d", 42);     // custom pad char A
row("%'.5d", 42);     // pad with .
row('%d', PHP_INT_MAX);
row('%d', PHP_INT_MIN);

echo "\n=== unsigned and bases ===\n";
row('%u', 42);
row('%u', -1);          // wraps
row('%b', 0);
row('%b', 1);
row('%b', 255);
row('%08b', 5);
row('%o', 8);
row('%o', 64);
row('%x', 255);
row('%X', 255);
row('%04x', 0xab);

echo "\n=== string formats ===\n";
row('%s', 'hello');
row('%10s|', 'hi');
row('%-10s|', 'hi');
row('%.3s', 'hello world');
row('%10.3s|', 'hello world');
row("%'_10s", 'abc');
row('%s', '');
row('%s', 0);
row('%s', null);
row('%s', true);
row('%s', false);

echo "\n=== float formats ===\n";
row('%f', 3.14);
row('%.2f', 3.14159);
row('%.0f', 3.7);
row('%10.2f', 3.14);
row('%-10.2f|', 3.14);
row('%+.2f', 3.14);
row('%+.2f', -3.14);
row('%e', 1234.5678);
row('%E', 1234.5678);
row('%.3e', 0.001234);
row('%g', 0.0001);
row('%g', 100000.5);
row('%.5g', 1234.5678);
row('%f', 0.1);
row('%f', 0.0);
row('%f', -0.0);

echo "\n=== character format ===\n";
row('%c', 65);
row('%c', 90);
row('%c', 97);
row('%c%c%c', 72, 105, 33);

echo "\n=== literal percent ===\n";
row('100%%');
row('%d%%', 50);
row('%%-%s-%%', 'mid');

echo "\n=== positional args ===\n";
row('%1$s and %2$s', 'a', 'b');
row('%2$s comes before %1$s', 'first', 'second');
row('%1$s %1$s %1$s', 'echo');
row('%1$s-%1$s-%2$s', 'x', 'y');

echo "\n=== mixed types coerced ===\n";
row('%d', '42');
row('%d', '42.7');
row('%d', '42abc');
row('%d', 'not a number');
row('%f', '3.14abc');
row('%s', 3.14);
row('%s', PHP_INT_MAX);

echo "\n=== width with very large output ===\n";
row('%50d|', 1);
row('%-50d|', 1);
row('%050d', 1);

echo "\n=== precision exceeds string length ===\n";
row('%.20s', 'short');
row('%30.20s|', 'short');

echo "\n=== zero values ===\n";
row('%d', 0);
row('%5d', 0);
row('%05d', 0);
row('%+d', 0);
row('%f', 0);
row('%.5f', 0);
row('%e', 0);
row('%g', 0);

echo "\n=== negative widths and edge cases ===\n";
row('%-+10d|', 42);
row('%-0+10d|', 42);
row("%-'A10s|", 'hi');
row('%5.2f', 3.14159);
row('%-5.2f|', 3.14159);
row('%+5.2f', 3.14);
row('%010.2f', 3.14);

echo "\n=== vsprintf via array ===\n";
echo "  " . vsprintf('%s is %d years old', ['Ada', 30]) . "\n";
echo "  " . vsprintf('%s/%s/%s', ['a', 'b', 'c']) . "\n";

echo "\n=== printf bytes ===\n";
$line = sprintf("%-20s %5d %8.2f\n", 'apple', 3, 1.5);
echo "  bytes: " . strlen($line) . "\n";
echo "  exact: [" . rtrim($line, "\n") . "]\n";

echo "\n=== many format specifiers in one ===\n";
$line = sprintf("[%s] %05d %+0.3f %X %b %c %o", 'tag', 42, 3.14, 255, 5, 65, 8);
echo "  " . $line . "\n";

echo "\n=== unicode in strings (byte-level width) ===\n";
row('%-10s|', 'café');           // 5 bytes -> 5 spaces of padding
row('%10s|', '中');               // 3 bytes -> 7 spaces of padding
row('%.3s', 'café');             // first 3 BYTES (cuts mid-utf8)

echo "\n=== float very-small / very-large ===\n";
row('%e', 1.5e-200);
row('%e', 1.5e200);
row('%.10e', 1e-10);
row('%g', 1.5e-200);
row('%g', 1.5e200);
