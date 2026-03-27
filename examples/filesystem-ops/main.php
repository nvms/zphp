<?php
// covers: touch, stat, chmod, chdir, getcwd, file_put_contents,
//   file_get_contents, file_exists, is_file, is_dir, filesize, mkdir,
//   unlink, rmdir, basename, dirname, realpath, sprintf

$tmp = sys_get_temp_dir() . '/zphp_fs_test_' . uniqid();
mkdir($tmp, 0755, true);
echo "=== touch ===\n";

$test_file = "$tmp/touchtest.txt";
$result = touch($test_file);
echo "touch new file: " . ($result ? 'ok' : 'fail') . "\n";
echo "file exists: " . (file_exists($test_file) ? 'yes' : 'no') . "\n";

// touch existing file
$result = touch($test_file);
echo "touch existing: " . ($result ? 'ok' : 'fail') . "\n";

// touch with specific timestamp
touch($test_file, 1700000000);
echo "touch with timestamp: ok\n";

echo "\n=== stat ===\n";
file_put_contents("$tmp/stattest.txt", "hello world, this is a test file");
$info = stat("$tmp/stattest.txt");
echo "size: " . $info['size'] . "\n";
echo "size (numeric): " . $info[7] . "\n";
echo "has atime: " . (isset($info['atime']) ? 'yes' : 'no') . "\n";
echo "has mtime: " . (isset($info['mtime']) ? 'yes' : 'no') . "\n";

// stat on different file sizes
$sizes = [0, 100, 1024, 4096];
foreach ($sizes as $size) {
    $f = "$tmp/size_$size.bin";
    file_put_contents($f, str_repeat('x', $size));
    $s = stat($f);
    echo sprintf("  %5d bytes -> stat size: %d\n", $size, $s['size']);
}

echo "\n=== chmod ===\n";
$chmod_file = "$tmp/chmod_test.txt";
file_put_contents($chmod_file, "test");

chmod($chmod_file, 0644);
echo "chmod 0644: ok\n";
echo "is_readable: " . (is_readable($chmod_file) ? 'yes' : 'no') . "\n";
echo "is_writable: " . (is_writable($chmod_file) ? 'yes' : 'no') . "\n";

chmod($chmod_file, 0444);
echo "chmod 0444: ok\n";
echo "is_readable: " . (is_readable($chmod_file) ? 'yes' : 'no') . "\n";

// restore so cleanup works
chmod($chmod_file, 0644);

echo "\n=== chdir ===\n";
$original = getcwd();
$result = chdir($tmp);
echo "chdir result: " . ($result ? 'ok' : 'fail') . "\n";
$new_cwd = getcwd();
echo "in temp dir: " . (basename($new_cwd) === basename($tmp) ? 'yes' : 'no') . "\n";

// go back
chdir($original);
echo "restored cwd: " . (getcwd() === $original ? 'yes' : 'no') . "\n";

echo "\n=== combined workflow ===\n";
// simulate a build process
$build_dir = "$tmp/build";
mkdir($build_dir);

$source_files = ['app.js', 'utils.js', 'config.js'];
foreach ($source_files as $file) {
    file_put_contents("$build_dir/$file", "// source: $file\nconsole.log('$file loaded');");
    touch("$build_dir/$file", 1700000000);
}

echo "created " . count($source_files) . " source files\n";

// check file info
foreach ($source_files as $file) {
    $path = "$build_dir/$file";
    $s = stat($path);
    echo sprintf("  %-12s %5d bytes\n", $file, $s['size']);
}

// create output
$output = '';
foreach ($source_files as $file) {
    $output .= file_get_contents("$build_dir/$file") . "\n";
}
file_put_contents("$build_dir/bundle.js", $output);
$bundle_stat = stat("$build_dir/bundle.js");
echo "bundle.js: " . $bundle_stat['size'] . " bytes\n";

// cleanup
foreach ($source_files as $file) unlink("$build_dir/$file");
unlink("$build_dir/bundle.js");
rmdir($build_dir);
unlink("$tmp/touchtest.txt");
unlink("$tmp/stattest.txt");
foreach ($sizes as $size) unlink("$tmp/size_$size.bin");
unlink($chmod_file);
rmdir($tmp);
echo "\ncleanup: ok\n";
