<?php
// sscanf/fscanf edge cases that follow php's scanf.c

function show($label, $v) {
    echo $label, ': ', preg_replace('/\s+/', ' ', var_export($v, true)), "\n";
}

function attempt($label, $fn) {
    try {
        show($label, $fn());
    } catch (Throwable $e) {
        echo $label, ': ', get_class($e), ': ', $e->getMessage(), "\n";
    }
}

// format errors
foreach (['%z', '%', '%5', '%l', '%[a', '%[^', '%[]', '%1$s %s', '%s %1$s', '%0$s', '%256$s', '%1$s %1$s', '%*%', '%2147483648$s'] as $f) {
    attempt("format " . json_encode($f), fn() => sscanf('abc def', $f));
}
attempt('too few vars', fn() => sscanf('a b', '%s %s', $x));
attempt('too many vars', fn() => sscanf('a', '%s', $x, $y));
attempt('xpg out of range', fn() => sscanf('a', '%2$s', $x));
attempt('xpg unassigned', fn() => sscanf('a b', '%1$s', $x, $y));

// array mode padding, eof and partial matches
show('empty input', sscanf('', '%d'));
show('empty input, two', sscanf('', '%d %s'));
show('whitespace only', sscanf("   \t", '%d'));
show('partial', sscanf('12 abc', '%d %d %s'));
show('literal mismatch', sscanf('a-b', 'a+%s'));
show('literal at eof', sscanf('ab', 'ab%s'));
show('percent literal', sscanf('50% off', '%d%% %s'));
show('xpg order', sscanf('one two three', '%3$s %1$s %2$s'));
show('xpg sparse', sscanf('x y', '%2$s %4$s'));
show('suppressed', sscanf('1 2 3', '%d %*d %d'));
show('size modifiers', sscanf('7 8 9', '%ld %hd %Ld'));

// by-reference mode
$r = sscanf('', '%d', $a);
show('eof by ref', [$r, $a]);
$r = sscanf('12 apples', '%d %s %n', $n, $what, $pos);
show('by ref', [$r, $n, $what, $pos]);
$r = sscanf('12', '%d %s', $n2, $w2);
show('by ref partial', [$r, $n2, $w2]);
$r = sscanf('a b', '%2$s %1$s', $p, $q);
show('by ref xpg', [$r, $p, $q]);

// %n counts consumed bytes
show('%n', sscanf('  hello world', '%s%n %s%n'));
show('%n first', sscanf('abc', '%n%s'));

// %c
show('%c', sscanf('abc', '%c%c%c'));
show('%c width', sscanf('abcdef', '%3c%2c'));
show('%c whitespace', sscanf(' x', '%c'));
show('%c stops at space', sscanf('ab cd', '%5c'));

// %s widths
show('%s width', sscanf('abcdefgh', '%3s%2s%s'));
show('%s skips', sscanf("  \n\tword", '%s'));

// character sets
show('set', sscanf('abc123def', '%[a-z]%[0-9]%[^0-9]'));
show('set bracket', sscanf(']]abc', '%[]]%s'));
show('set dash', sscanf('a-b-c+', '%[-a-c]%s'));
show('set trailing dash', sscanf('-a-x', '%[a-]%s'));
show('set reversed range', sscanf('dcba1', '%[z-a]%s'));
show('set negated bracket', sscanf('abc]def', '%[^]]]%s'));
show('set no match', sscanf('123', '%[a-z]%s'));
show('set width', sscanf('aaaaaa', '%3[a]%s'));
show('set no skip', sscanf('  ab', '%[ a]%s'));
show('set high bytes', sscanf("abc\xe9\xff!", '%[a-z]%[^!]%s'));

// integers
show('%d', sscanf('-42 +17 0012', '%d %d %d'));
show('%d overflow', sscanf('99999999999999999999 -99999999999999999999', '%d %d'));
show('%d width', sscanf('123456', '%2d%3d%d'));
show('%d sign only', sscanf('- 5', '%d %d'));
show('%i bases', sscanf('0x1f 017 19 -0x10', '%i %i %i %i'));
show('%i 0x tail', sscanf('0xg', '%i%s'));
show('%i 09', sscanf('09', '%i%s'));
show('%x', sscanf('ff 0X1A -a 0x', '%x %x %x %x'));
show('%X', sscanf('DEADbeef', '%X'));
show('%o', sscanf('777 8', '%o %o'));
show('%u', sscanf('5 -5 18446744073709551615 99999999999999999999', '%u %u %u %u'));
show('%D', sscanf('31', '%D'));
show('%d long', sscanf(str_repeat('1', 70), '%d%s'));

// floats
show('%f', sscanf('3.14 -2.5e3 .5 1. +7', '%f %f %f %f %f'));
show('%e %E %g', sscanf('1e10 2E-3 4.5', '%e %E %g'));
show('%f bad exponent', sscanf('1.5e+x', '%f%s'));
show('%f e alone', sscanf('2ex', '%f%s'));
show('%f dot', sscanf('.x', '%f%s'));
show('%f zero', sscanf('-0 -0.0', '%f %f'));
show('%f range', sscanf('1e999 -1e999 1e-400', '%f %f %f'));
show('%f width', sscanf('123.456', '%4f%f'));
show('%f two dots', sscanf('1.2.3', '%f%s'));

// NUL bytes end both strings
show('nul input', sscanf("ab\0cd", '%s%s'));
show('nul format', sscanf('12 34', "%d\0%d"));
show('nul %n', sscanf("ab\0cd", '%s%n'));

// argument coercion
show('int args', sscanf(12345, 123));
class Str { function __toString(): string { return "7 up"; } }
show('stringable', sscanf(new Str, '%d %s'));
attempt('array arg', fn() => sscanf([], '%d'));

// fscanf
$file = tempnam(sys_get_temp_dir(), 'scanf');
file_put_contents($file, "10 apples\nname: zed\n\n" . str_repeat('x', 3000) . " end\nlast");
$fh = fopen($file, 'r');
show('fscanf line 1', fscanf($fh, '%d %s'));
$r = fscanf($fh, 'name: %s', $name);
show('fscanf by ref', [$r, $name]);
show('fscanf blank line', fscanf($fh, '%s'));
$r = fscanf($fh, '%s %s', $long, $end);
show('fscanf long line', [$r, strlen($long), $end]);
show('fscanf no newline', fscanf($fh, '%s'));
show('fscanf eof', fscanf($fh, '%s'));
$r = fscanf($fh, '%s', $gone);
show('fscanf eof by ref', [$r, $gone ?? null]);
attempt('fscanf bad format at eof', fn() => fscanf($fh, '%q'));
rewind($fh);
attempt('fscanf bad format', fn() => fscanf($fh, '%q'));
show('fscanf after bad format', fscanf($fh, 'name: %s'));
fclose($fh);
attempt('fscanf closed', fn() => fscanf($fh, '%s'));
attempt('fscanf not resource', fn() => fscanf('x', '%s'));

$wh = fopen($file, 'a');
show('fscanf write only', fscanf($wh, '%s'));
show('fgets write only', fgets($wh));
fclose($wh);
unlink($file);

$m = fopen('php://memory', 'w+');
class Obj { function __toString(): string { return "8 bits\n"; } }
fwrite($m, new Obj);
rewind($m);
show('fwrite stringable', fscanf($m, '%d %s'));
attempt('fwrite array', fn() => fwrite($m, []));
fclose($m);
