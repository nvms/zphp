<?php
// proc_open's environment: each value as a string (an array warns), an
// empty value left out, a value under an int key passed as written

class Name {
    public function __toString(): string { return 'from-object'; }
}

$env = [
    'PATH' => getenv('PATH'),
    'LIST' => [1, 2],
    'EMPTY' => '',
    'NUM' => 42,
    'OBJ' => new Name,
    'RAW=as-is',
];
$code = 'foreach (["LIST", "EMPTY", "NUM", "OBJ", "RAW"] as $k) { echo $k, "=", var_export(getenv($k), true), "\n"; }';
$proc = proc_open([PHP_BINARY, '-n', '-r', $code], [1 => ['pipe', 'w']], $pipes, null, $env);
echo stream_get_contents($pipes[1]);
fclose($pipes[1]);
var_dump(proc_close($proc));
