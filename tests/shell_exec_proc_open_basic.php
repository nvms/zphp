<?php
echo trim(shell_exec("echo hello")), "\n";
echo trim(shell_exec("printf 'abc'")), "\n";

$out = exec("echo line1; echo line2", $arr, $code);
echo "out=", $out, " code=$code\n";
print_r($arr);

$arr = [];
exec("echo a; echo b; echo c", $arr);
print_r($arr);

$ret = system("echo systest", $code);
echo "code=$code ret=$ret\n";

ob_start();
passthru("echo from-passthru");
$out = ob_get_clean();
echo "[", trim($out), "]\n";

echo escapeshellarg("hello world"), "\n";
echo escapeshellarg("it's"), "\n";
echo escapeshellarg(""), "\n";

echo escapeshellcmd("a;b|c&d"), "\n";

$fp = popen("echo popen", "r");
echo trim(fgets($fp)), "\n";
pclose($fp);

$fp = popen("cat > /tmp/zphp_popen_w.txt", "w");
fwrite($fp, "written by popen\n");
pclose($fp);
echo trim(file_get_contents("/tmp/zphp_popen_w.txt")), "\n";
@unlink("/tmp/zphp_popen_w.txt");

$proc = proc_open("echo proc_test", [1 => ["pipe", "w"]], $pipes);
echo trim(stream_get_contents($pipes[1])), "\n";
fclose($pipes[1]);
proc_close($proc);

$proc = proc_open("sleep 0.1", [], $pipes);
$status = proc_get_status($proc);
echo isset($status["command"]) ? "y" : "n", "\n";
echo isset($status["running"]) ? "y" : "n", "\n";
echo isset($status["pid"]) ? "y" : "n", "\n";
proc_close($proc);

echo function_exists("shell_exec") ? "y" : "n", "\n";
echo function_exists("exec") ? "y" : "n", "\n";
echo function_exists("system") ? "y" : "n", "\n";
echo function_exists("passthru") ? "y" : "n", "\n";
echo function_exists("popen") ? "y" : "n", "\n";
echo function_exists("proc_open") ? "y" : "n", "\n";

$last = exec("true", $a, $c);
echo "true: code=$c\n";
$last = exec("false", $a, $c);
echo "false: code=$c\n";
