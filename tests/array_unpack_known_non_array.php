<?php
// an array literal whose elements are all known when it compiles is built
// then: unpacking a known non-array in it is a compile error; one with a
// run-time element unpacks at run time

$cases = [
    'var_dump([...42]);',
    'var_dump([1, "a" => 2, ...null]);',
    'var_dump([...[1, 2], ..."text"]);',
    'var_dump([...[1, [2]], ...["k" => true]]);',
    '$x = 5; try { var_dump([...$x]); } catch (Error $e) { echo $e->getMessage(), "\n"; }',
    'function f() { return [...1.5]; } echo "unreachable";',
];
$file = sys_get_temp_dir() . '/zphp_unpack_known_' . getmypid() . '.php';
foreach ($cases as $code) {
    file_put_contents($file, "<?php\n$code\n");
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 -d fatal_error_backtraces=0 ' . escapeshellarg($file) . ' 2>&1');
    echo str_replace([$file, str_replace('/', DIRECTORY_SEPARATOR, $file)], 'FILE', $out), "\n";
}
unlink($file);
