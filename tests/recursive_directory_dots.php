<?php
// without SKIP_DOTS a recursive walk lists . and .. in every directory but
// never descends into them

$root = sys_get_temp_dir() . '/zphp_rdi_dots_' . getmypid();
mkdir("$root/src/lib", 0777, true);
touch("$root/src/lib/util.php");
touch("$root/src/main.php");
touch("$root/README");

$paths = [];
$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root), RecursiveIteratorIterator::SELF_FIRST);
foreach ($it as $path => $info) {
    $paths[] = $it->getDepth() . ' ' . substr($path, strlen($root) + 1) . ($info->isDir() ? '/' : '');
}
sort($paths);
echo implode("\n", $paths), "\n";

$files = 0;
foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root)) as $info) {
    if ($info->isFile()) {
        $files++;
    }
}
echo "files: $files\n";

unlink("$root/src/lib/util.php");
unlink("$root/src/main.php");
unlink("$root/README");
rmdir("$root/src/lib");
rmdir("$root/src");
rmdir($root);
