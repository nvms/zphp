<?php
// the cli's --ri prints one extension's information, named in any case
foreach (['spl', 'Json', 'reflection'] as $name) {
    echo shell_exec(escapeshellarg(PHP_BINARY) . ' --ri ' . escapeshellarg($name));
}
exec(escapeshellarg(PHP_BINARY) . ' --ri no_such_extension', $out, $status);
var_dump($out, $status);
