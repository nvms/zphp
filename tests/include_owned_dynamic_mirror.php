<?php
$file = sys_get_temp_dir() . '/zphp_owned_include_' . getmypid() . '.php';
file_put_contents($file, '<?php ${$name} = "replacement-" . 2;');
function includeOwnedMirror(string $file): void {
    $value = 'original-' . 1;
    $name = 'value';
    include $file;
    gc_collect_cycles();
    var_dump($value);
    $value .= '-suffix';
    var_dump($value);
}
includeOwnedMirror($file);
unlink($file);
