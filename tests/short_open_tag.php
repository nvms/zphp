<?php
// short_open_tag decides at lex time whether `<?` opens php code

$file = tempnam(sys_get_temp_dir(), 'sot');
file_put_contents($file, "<?\necho \"short tag\\n\";\n?>\nbetween <?echo 'inline'; ?>\n<?= 'echo tag' ?>\n<?php echo \"long tag\\n\";\n");

foreach (['1', 'on', '0', 'off'] as $setting) {
    echo "short_open_tag=$setting\n";
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d short_open_tag=' . $setting . ' ' . escapeshellarg($file) . ' 2>&1');
    echo str_replace([$file, str_replace('/', DIRECTORY_SEPARATOR, $file)], 'FILE', $out), "\n";
}

// token_get_all reads the same way
$code = "<?\necho 1;";
foreach (['1', '0'] as $setting) {
    $script = tempnam(sys_get_temp_dir(), 'sot');
    file_put_contents($script, '<?php foreach (token_get_all(' . var_export($code, true) . ') as $t) echo is_array($t) ? token_name($t[0]) : $t, "\n";');
    echo shell_exec(escapeshellarg(PHP_BINARY) . ' -d short_open_tag=' . $setting . ' ' . escapeshellarg($script) . ' 2>&1');
    unlink($script);
}
unlink($file);
