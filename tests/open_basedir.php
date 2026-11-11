<?php
// open_basedir confines file access to a list of directories; "." is the
// working directory at the time of each check, and at run time the setting
// may only be narrowed
$base = sys_get_temp_dir() . "/zphp_open_basedir_" . getmypid();
@mkdir("$base/in/sub", 0777, true);
@mkdir("$base/out", 0777, true);
file_put_contents("$base/in/a.txt", "inside");
file_put_contents("$base/out/b.txt", "outside");
@symlink("$base/out/b.txt", "$base/in/escape.txt");
file_put_contents("$base/in/inc.php", "<?php echo \"included\\n\";");
file_put_contents("$base/out/inc.php", "<?php echo \"should not run\\n\";");

ini_set("include_path", ".");
set_error_handler(function ($no, $msg) use ($base) {
    echo str_replace($base, "BASE", $msg), "\n";
    return true;
});

chdir("$base/in");
var_dump(ini_set("open_basedir", "$base/in"));
var_dump(str_replace($base, "BASE", ini_get("open_basedir")));
var_dump(ini_set("open_basedir", $base));
var_dump(ini_set("open_basedir", ""));

var_dump(file_exists("a.txt"), file_exists("../out/b.txt"), is_file("../out"), is_dir("sub"));
var_dump(file_get_contents("a.txt"), file_get_contents("../out/b.txt"));
var_dump(file_get_contents("escape.txt"));
var_dump(fopen("../out/b.txt", "r"));
var_dump(file_put_contents("../out/c.txt", "x"), file_put_contents("sub/c.txt", "x"));
var_dump(copy("../out/b.txt", "copy.txt"), copy("a.txt", "../out/copy.txt"));
var_dump(rename("sub/c.txt", "../out/c.txt"), unlink("../out/b.txt"), unlink("sub/c.txt"));
var_dump(mkdir("../out/new"), mkdir("sub/new"), rmdir("sub/new"), rmdir("../out"));
var_dump(touch("../out/t.txt"), chmod("../out/b.txt", 0644));
var_dump(filesize("../out/b.txt"), stat("../out/b.txt"), filemtime("a.txt") > 0);
var_dump(opendir("../out"), scandir("../out"));
var_dump(glob("../*"), glob("../out/*"), glob("*.txt"));
var_dump(realpath("../out"), realpath("sub") === "$base/in/sub");
var_dump(tempnam("../out", "t"));
var_dump(chdir("../out"), chdir("sub"), basename(getcwd()));
var_dump(readlink("../escape.txt") === "$base/out/b.txt");
var_dump(include "../inc.php");
var_dump(include "$base/out/inc.php");
var_dump(error_log("x", 3, "$base/out/log.txt"));
var_dump(ini_set("error_log", "$base/out/log.txt"));

// "." follows the working directory
chdir("$base/in");
var_dump(str_replace($base, "BASE", ini_set("open_basedir", ".")));
var_dump(file_exists("$base/in/a.txt"), file_exists("sub"));
chdir("sub");
var_dump(file_exists("../a.txt"));

restore_error_handler();

exec("rm -rf " . escapeshellarg($base));
