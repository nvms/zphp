<?php
// auto_prepend_file and auto_append_file run around the script in its
// global scope; the prepended file counts as included, and exit in it ends
// everything
$dir = sys_get_temp_dir() . '/zphp_auto_files_' . getmypid();
@mkdir($dir);
file_put_contents("$dir/prepend.php", '<?php echo "prepend\n"; $shared = "from prepend"; function helper() { return "helper"; }');
file_put_contents("$dir/append.php", '<?php echo "append: $shared, ", count(get_included_files()), "\n";');
file_put_contents("$dir/exit.php", '<?php echo "exiting\n"; exit(3);');
file_put_contents("$dir/main.php", '<?php echo "main: $shared, ", helper(), "\n"; $shared = "from main"; var_dump((include_once __DIR__ . "/prepend.php"));');
file_put_contents("$dir/main_exit.php", '<?php echo "main ran\n"; exit;');

function run($dir, $ini, $script) {
    $cmd = escapeshellarg(PHP_BINARY) . ' -n';
    foreach ($ini as $k => $v) $cmd .= ' -d ' . escapeshellarg("$k=$v");
    $cmd .= ' ' . escapeshellarg("$dir/$script") . ' 2>&1';
    exec($cmd, $out, $status);
    echo implode("\n", $out), "\n[status $status]\n";
}

run($dir, ['auto_prepend_file' => "$dir/prepend.php", 'auto_append_file' => "$dir/append.php"], 'main.php');
run($dir, ['auto_prepend_file' => "$dir/exit.php", 'auto_append_file' => "$dir/append.php"], 'main.php');
run($dir, ['auto_prepend_file' => "$dir/prepend.php", 'auto_append_file' => "$dir/append.php"], 'main_exit.php');
run($dir, ['auto_prepend_file' => 'none', 'auto_append_file' => ''], 'main_exit.php');

foreach (glob("$dir/*") as $f) unlink($f);
rmdir($dir);
