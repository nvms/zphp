<?php
// an underscore separates two digits of a number and nothing else; anywhere
// else the number ends before it

var_dump(1_000);
var_dump(1_000.5_5, 1_0e1_0, .5_5, 0b1_0, 0o1_7, 01_7, 0xA_b);

foreach (['1__2', '100_', '1_.5', '1._5', '0x_1', '0b_1', '0o_1', '1_e2', '1e_2', '0x1__2', '1_000_'] as $literal) {
    $file = tempnam(sys_get_temp_dir(), 'num');
    file_put_contents($file, "<?php\nvar_dump($literal);\n");
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    echo $literal, ': ', str_replace($file, 'FILE', $out);
    unlink($file);
}
