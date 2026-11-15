<?php
// phpinfo() and phpcredits() print php's text layout in the cli

// distributions add their packagers to the credits; leave that table out
function credits(int $flags): void {
    ob_start();
    $r = phpcredits($flags);
    $out = ob_get_clean();
    echo preg_replace('/\n +Debian Packaging +\n[^\n]*\n/', '', $out);
    var_dump($r);
}

$_ENV = [];
$_SERVER = ['name' => 'value', 7 => 'seven', 'nested' => ['a' => [1, 2]], 'empty' => '', 'float' => 1.5, 'bool' => true];
$PHP_SELF = 'self.php';
$PHP_AUTH_USER = 42;
$GLOBALS["PHP_AUTH_TYPE"] = "basic";
${"PHP_AUTH_PW"} = 7;
var_dump(phpinfo(INFO_VARIABLES));
var_dump(phpinfo(0));
var_dump(phpinfo(INFO_LICENSE));
ob_start();
var_dump(phpinfo(INFO_CONFIGURATION | INFO_LICENSE) === true);
ob_end_clean();

credits(CREDITS_GROUP | CREDITS_QA);
credits(0);
// the docs and sapi tables are left out: distributions add their packagers there
credits(CREDITS_WEB | CREDITS_GENERAL);

ob_start();
phpinfo();
$all = ob_get_clean();
$lines = explode("\n", $all);
var_dump($lines[0], strtok($lines[1], "="));
foreach (["Configuration", "Core", "date", "json", "standard", "Additional Modules", "Environment", "PHP Variables", "PHP Credits", "PHP License"] as $heading) {
    var_dump(in_array($heading, $lines, true));
}
foreach (["json support => enabled", "Directive => Local Value => Master Value", "allow_url_fopen => On => On", "Module Name"] as $line) {
    var_dump(in_array($line, $lines, true));
}

// a directive set at run time shows its new local value beside the master
ini_set('precision', '10');
ob_start();
phpinfo(INFO_CONFIGURATION);
$config = explode("\n", ob_get_clean());
var_dump(in_array("precision => 10 => 14", $config, true));

// the cli's -i prints phpinfo() without the credits; -e changes nothing a script sees
$php = escapeshellarg(PHP_BINARY);
$info = shell_exec("$php -n -i");
var_dump(strtok($info, "\n"), str_contains($info, "PHP Credits"), str_contains($info, "PHP License"));
var_dump(shell_exec("$php -n -e -r \"echo 6 * 7;\""));
