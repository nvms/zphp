<?php
// a constant expression's class constant fetch on a literal that isn't a
// string fails to compile: the literal names no class
function run(string $code): void
{
    $file = tempnam(sys_get_temp_dir(), 'constexpr');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    echo str_replace($file, 'FILE', $out), "\n";
    unlink($file);
}
run('const B = []::{A};');
run('class Z { const W = 1; const V = Z::{"W"}; } echo Z::V;');
