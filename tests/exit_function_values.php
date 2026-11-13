<?php
// exit() is a function taking string|int: a string is printed, anything else
// is the status by php's weak rules, or a TypeError; die is its alias

function run(string $code, string $flags = ''): void
{
    $file = tempnam(sys_get_temp_dir(), 'exit');
    file_put_contents($file, "<?php\n" . $code);
    exec(escapeshellarg(PHP_BINARY) . " $flags -d display_errors=1 -d log_errors=0 -d error_reporting=-1 " . escapeshellarg($file) . ' 2>&1', $output, $status);
    echo str_replace($file, 'FILE', implode("\n", $output)), "\n-> status $status\n";
    unlink($file);
}

foreach (['null', 'false', 'true', '0', '7', '300', '-1', '10.0', '15.5', '1e100', '"text"', '"5"', '[]', 'STDERR', 'new stdClass',
          'new class { function __toString(): string { return "stringable"; } }'] as $value) {
    foreach (['exit', 'die'] as $fn) {
        echo "$fn($value): ";
        run("try { $fn($value); } catch (Throwable \$e) { echo get_class(\$e), ': ', \$e->getMessage(), \"\\n\"; }");
    }
}
run('declare(strict_types=1); try { exit(true); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }');
run('$f = die(...); var_dump($f); $f(3);');
run('namespace Space; $f = exit(...); echo (new \ReflectionFunction($f))->getName(), "\n"; exit(4);');
run('trigger_error("shown with no ini"); var_dump(ini_get("display_errors"), ini_get("log_errors"));', '-n');
run('trigger_error("shown with no ini"); var_dump(ini_get("display_errors"), ini_get("log_errors"));', '--no-php-ini');
