<?php
// SimpleXML/XMLReader/DOMDocument not in zphp (architectural)

// DateTime methods
$d = new DateTime("2024-06-15");
echo $d->getTimestamp(), "\n";
$d->setTimestamp(1718409600);
echo $d->format("Y-m-d H:i:s"), "\n";

$d->setDate(2024, 12, 25);
echo $d->format("Y-m-d"), "\n";
$d->setTime(14, 30, 45);
echo $d->format("Y-m-d H:i:s"), "\n";

// DateTimeImmutable equivalents
$di = new DateTimeImmutable("2024-06-15");
$di2 = $di->setTime(0, 0, 0);
echo $di->format("Y-m-d H:i:s"), "|", $di2->format("Y-m-d H:i:s"), "\n";

$di3 = $di->setDate(2025, 1, 1);
echo $di->format("Y-m-d"), "|", $di3->format("Y-m-d"), "\n";

// DateTime::diff total
$a = new DateTime("2024-01-01");
$b = new DateTime("2024-12-31");
$diff = $a->diff($b);
echo $diff->days, "\n"; // 365 (leap year)

$a = new DateTime("2024-01-01 00:00:00");
$b = new DateTime("2024-01-01 12:30:45");
$diff = $a->diff($b);
echo "{$diff->h}:{$diff->i}:{$diff->s}\n"; // 12:30:45

// strftime replacement (PHP 8.1+ deprecates)
$ts = mktime(14, 30, 45, 6, 15, 2024);
echo date("Y-m-d", $ts), "\n";
echo date("D, d M Y H:i:s", $ts), "\n"; // Sat, 15 Jun 2024 14:30:45
echo date("l, jS F", $ts), "\n";        // Saturday, 15th June

// Intl extension not in zphp (architectural)

// number_format vs NumberFormatter
echo number_format(1234567.89, 2, ".", ","), "\n";

// Phar functions
echo function_exists("phar") ? "y" : "n", "\n";
echo class_exists("Phar") ? "y" : "n", "\n";
// PharData class not implemented (architectural)

// FFI/Random\Engine not in zphp (architectural)

// DOMDocument not implemented (architectural)

// Random\Randomizer
if (class_exists("Random\\Randomizer")) {
    $r = new Random\Randomizer();
    $i = $r->getInt(1, 100);
    echo gettype($i), "\n";
    echo $i >= 1 && $i <= 100 ? "in-range\n" : "no\n";
}

// timestamp accuracy
$t = time();
$tb = time();
echo $tb >= $t ? "monotonic\n" : "no\n";

// hrtime monotonic
$h1 = hrtime(true);
usleep(1000); // 1ms
$h2 = hrtime(true);
echo $h2 > $h1 ? "hr-mono\n" : "no\n";

// constants
echo PHP_INT_MAX, "\n";
echo PHP_INT_MIN, "\n";
echo PHP_INT_SIZE, "\n";
echo PHP_FLOAT_DIG, "\n";
echo PHP_FLOAT_EPSILON < 1e-10 ? "tiny" : "big", "\n";
echo PHP_FLOAT_MIN > 0 ? "pos" : "no", "\n";
echo PHP_FLOAT_MAX > 1e10 ? "big" : "no", "\n";
echo PHP_EOL === "\n" || PHP_EOL === "\r\n" ? "ok\n" : "no\n";
echo PHP_OS_FAMILY, "\n"; // depends
echo strlen(PHP_OS) > 0 ? "os-set\n" : "no\n";
echo PHP_SAPI, "\n"; // cli
