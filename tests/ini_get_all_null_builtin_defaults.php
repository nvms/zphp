<?php
// directives php registers without a compiled-in default report null in
// ini_get_all() until something sets them, and ini_get() reads ""
$code = <<<'PHP'
$all = ini_get_all(null, true);
foreach (['error_append_string', 'error_prepend_string', 'user_agent', 'open_basedir', 'auto_prepend_file', 'sys_temp_dir', 'request_order', 'precision'] as $name) {
    echo $name, ': ', var_export($all[$name]['global_value'], true), ' ', var_export($all[$name]['local_value'], true), ' ', var_export($all[$name]['builtin_default_value'], true), ' ', var_export(ini_get($name), true), "\n";
}
ini_set('error_append_string', 'BAR');
$all = ini_get_all(null, true);
echo var_export($all['error_append_string'], true), "\n";
PHP;
echo shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d error_append_string=FOO -r ' . escapeshellarg($code) . ' 2>&1');
