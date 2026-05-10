<?php
echo sprintf("%d", 42), "\n";
echo sprintf("%5d", 42), "\n";
echo sprintf("%-5d|", 42), "\n";
echo sprintf("%05d", 42), "\n";
echo sprintf("%+d %+d", 5, -5), "\n";
echo sprintf("% d % d", 5, -5), "\n";

echo sprintf("%s", "abc"), "\n";
echo sprintf("%10s", "abc"), "\n";
echo sprintf("%-10s|", "abc"), "\n";
echo sprintf("%.3s", "abcdef"), "\n";
echo sprintf("%10.3s", "abcdef"), "\n";

echo sprintf("%f", 3.14), "\n";
echo sprintf("%.2f", 3.14159), "\n";
echo sprintf("%10.2f", 3.14), "\n";
echo sprintf("%-10.2f|", 3.14), "\n";
echo sprintf("%010.2f", 3.14), "\n";
echo sprintf("%+.2f %+.2f", 3.14, -3.14), "\n";

echo sprintf("%e", 12345.6789), "\n";
echo sprintf("%.2e", 12345.6789), "\n";
echo sprintf("%E", 0.00001234), "\n";

echo sprintf("%g", 0.0001), "\n";
echo sprintf("%g", 12345.6789), "\n";
echo sprintf("%G", 1e-10), "\n";

echo sprintf("%x", 255), "\n";
echo sprintf("%X", 255), "\n";
echo sprintf("%08x", 255), "\n";
try { sprintf("%#x", 255); echo "no\n"; } catch (\ValueError $e) { echo "ve-hash\n"; }

echo sprintf("%o", 8), "\n";
echo sprintf("%o", 64), "\n";
echo sprintf("%05o", 8), "\n";

echo sprintf("%b", 10), "\n";
echo sprintf("%b", 255), "\n";
echo sprintf("%010b", 10), "\n";

echo sprintf("%c", 65), "\n";
echo sprintf("%c", 0x41), "\n";

echo sprintf("100%%"), "\n";
echo sprintf("%d%% done", 50), "\n";

echo sprintf("%2\$s %1\$s", "world", "hello"), "\n";
echo sprintf("%1\$s %1\$s", "again"), "\n";
echo sprintf("%3\$d-%1\$d-%2\$d", 1, 2, 3), "\n";
echo sprintf("%1\$05d", 42), "\n";

echo sprintf("[%'*10s]", "hi"), "\n";
echo sprintf("[%'-10s]", "hi"), "\n";
echo sprintf("[%'.10d]", 42), "\n";

echo sprintf("%5.2f", 3.14159), "\n";
echo sprintf("%-5.2f|", 3.14), "\n";

echo sprintf("%.0f", 3.7), "\n";
echo sprintf("%.10f", 1.0 / 3), "\n";

echo sprintf("[%5d]", 0), "\n";
echo sprintf("[%-5d]", 0), "\n";
echo sprintf("[%05d]", 0), "\n";

echo sprintf("[%5d]", -42), "\n";
echo sprintf("[%-5d]", -42), "\n";
echo sprintf("[%05d]", -42), "\n";

printf("%d\n", 42);
printf("%s %d\n", "n=", 42);

$r = sprintf("a=%d b=%d", 5, 10);
echo $r, "\n";

$out = vsprintf("[%d %s]", [42, "hi"]);
echo $out, "\n";

ob_start();
vprintf("%d-%s", [99, "name"]);
$out = ob_get_clean();
echo $out, "\n";

echo sprintf("%.2f", 0), "\n";
echo sprintf("%.2f", 0.0), "\n";
echo sprintf("%d", 0), "\n";
echo sprintf("%5d|", 0), "\n";

echo sprintf("%d", -0), "\n";
echo sprintf("%.0f", -0.5), "\n";
echo sprintf("%.0f", 0.5), "\n";

$big = 1234567890;
echo sprintf("%d", $big), "\n";
echo sprintf("%015d", $big), "\n";
try { sprintf("%,d", $big); echo "no\n"; } catch (\ValueError $e) { echo "ve-comma\n"; }

echo sprintf("%s", null), "\n";
echo sprintf("[%s]", ""), "\n";
echo sprintf("[%5s]", ""), "\n";

echo sprintf("%s/%d/%f", "a", 1, 2.5), "\n";

$out = sprintf("%4d %-10s %.3f", 42, "name", 3.14159);
echo "[", $out, "]\n";

echo sprintf("%05.2f", 3.14), "\n";
// %-05.2f corner case (architectural - PHP pads right with '0', zphp pads with space)

echo sprintf("%5.0f", 1234.5), "\n";

echo sprintf("[%6.2e]", 12345.6789), "\n";
echo sprintf("[%-12.2e]", 0.000123), "\n";

echo sprintf("%05x", 0xff), "\n";
echo sprintf("%-5x|", 0xff), "\n";
