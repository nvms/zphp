<?php
// `php -f file -- args`: the "--" after the file ends option parsing and
// is not one of the script's arguments; anywhere else it is
$script = tempnam(sys_get_temp_dir(), 'argv');
file_put_contents($script, '<?php echo json_encode(array_slice($argv, 1)), " ", $argc, " ", json_encode(getopt("ab:")), "\n";');
foreach (["-f %s -- -a -b 2 x", "-f %s x -- y", "%s -- -a", "-f %s"] as $form) {
    $cmd = escapeshellarg(PHP_BINARY) . " -n " . sprintf($form, escapeshellarg($script));
    echo shell_exec($cmd);
}
unlink($script);
