<?php
// regression: a file required at global scope IS the global scope, so a
// top-level variable it assigns is visible to `global $x` immediately -
// even from a function called while the require is still executing.
// previously zphp gave the included file a private copy of the caller's
// vars and only merged them back when the require RETURNED, so a function
// invoked mid-require saw the variable as unset. this is what broke
// WordPress 7.0 boot: wp_set_wpdb_vars() does `global $table_prefix` while
// still inside the wp-config.php require, read NULL, and every table name
// lost its prefix.
$dir = sys_get_temp_dir() . '/zphp_reqscope_' . getmypid();
@mkdir($dir);
file_put_contents("$dir/b.php", '<?php $shared = "set-in-b"; require "' . $dir . '/c.php"; echo "from-fn: " . reader() . "\n";');
file_put_contents("$dir/c.php", '<?php function reader() { global $shared; return $shared ?? "UNSET"; }');

require "$dir/b.php";

// after the require returns, the var is also a normal global
echo "after-require plain: " . ($shared ?? 'UNSET') . "\n";
function reader2() { global $shared; return $shared ?? 'UNSET'; }
echo "after-require fn: " . reader2() . "\n";

// nested two levels deep
file_put_contents("$dir/d.php", '<?php $deep = "deep-val"; require "' . $dir . '/e.php"; echo "deep-fn: " . deepreader() . "\n";');
file_put_contents("$dir/e.php", '<?php function deepreader() { global $deep; return $deep ?? "UNSET"; }');
file_put_contents("$dir/dd.php", '<?php require "' . $dir . '/d.php";');
require "$dir/dd.php";

@unlink("$dir/b.php"); @unlink("$dir/c.php"); @unlink("$dir/d.php");
@unlink("$dir/e.php"); @unlink("$dir/dd.php"); @rmdir($dir);
