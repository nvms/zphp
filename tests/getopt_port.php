<?php
// getopt() as php's php_getopt parses $_SERVER['argv']: clustered short
// options, -xvalue / -x=value / -x value, optional values, long options
// with = or a separate value, repeated options gathered into arrays,
// numeric option names as int keys, and $rest_index
$script = tempnam(sys_get_temp_dir(), 'getopt');
file_put_contents($script, <<<'PHP'
<?php
$rest = null;
$opts = getopt(getenv("GETOPT_SHORT"), json_decode(getenv("GETOPT_LONG")), $rest);
ksort($opts);
echo json_encode($opts), " ", $rest, "\n";
PHP);
$cases = [
    ['ab:c::', '[]', '-a -b 1 -c2 rest'],
    ['ab:c::', '[]', '-ab2 -c -a'],
    ['v', '[]', '-v -v -vvv'],
    ['a:', '[]', '-a=x -a y -a'],
    ['', '["long:", "flag", "opt::"]', '--long=1 --long 2 --flag --opt --opt=3 x'],
    ['', '["flag"]', '--flag -- --flag'],
    ['12', '["0", "10"]', '-1 -2 --10 --0'],
    ['ab', '[]', '-a - -b'],
    ['a', '[]', '-x -a'],
    ['a:', '[]', '-a'],
];
foreach ($cases as [$short, $long, $args]) {
    $cmd = "GETOPT_SHORT=" . escapeshellarg($short) . " GETOPT_LONG=" . escapeshellarg($long) . " " . escapeshellarg(PHP_BINARY) . " -n " . escapeshellarg($script) . " " . $args;
    echo shell_exec($cmd . " 2>&1");
}
unlink($script);
