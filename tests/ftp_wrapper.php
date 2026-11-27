<?php
// the ftp:// and ftps:// wrapper against a small ftp server in a forked
// child: transfers over passive data connections, listings, stat, the
// one-command operations, ftps with TLS on both connections, and the
// errors php reports for each way they fail
$dir = __DIR__ . '/fixtures/tls';
set_error_handler(function (int $level, string $message) {
    echo "warning: ", preg_replace(['/:\d{4,5}\b/', '/ in \S+ on line \d+/'], [':PORT', ''], $message), "\n";
    return true;
});

// the server: one connection after another, each command logged for the
// client to print, the files kept in memory
function ftp_server(string $dir, int $conns): array
{
    $server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
    $data_server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
    [, $port] = explode(':', stream_socket_get_name($server, false));
    [, $data_port] = explode(':', stream_socket_get_name($data_server, false));
    $log = sys_get_temp_dir() . '/zphp_ftp_log_' . getmypid();
    @unlink($log);
    $pid = pcntl_fork();
    if ($pid !== 0) {
        fclose($server);
        fclose($data_server);
        return [(int) $port, $pid, $log];
    }
    set_error_handler(fn () => true);
    $files = ['/hello.txt' => "hello over ftp\n", '/dir/a.txt' => 'a', '/dir/b.txt' => 'b'];
    $dirs = ['/', '/dir'];
    for ($n = 0; $n < $conns; $n++) {
        $c = stream_socket_accept($server, 10);
        if (!$c) break;
        fwrite($c, "220 ready\r\n");
        $tls = false;
        $prot = false;
        $pending = null;
        while (($line = fgets($c)) !== false) {
            $line = rtrim($line, "\r\n");
            file_put_contents($log, $line . "\n", FILE_APPEND);
            [$cmd, $arg] = array_pad(explode(' ', $line, 2), 2, '');
            switch ($cmd) {
                case 'AUTH':
                    if ($arg === 'TLS' && str_contains($line, 'TLS')) {
                        fwrite($c, "234 ok\r\n");
                        stream_context_set_option($c, 'ssl', 'local_cert', "$dir/server.pem");
                        stream_socket_enable_crypto($c, true, STREAM_CRYPTO_METHOD_TLS_SERVER);
                        $tls = true;
                    } else fwrite($c, "504 no\r\n");
                    break;
                case 'PBSZ': fwrite($c, "200 ok\r\n"); break;
                case 'PROT': $prot = $arg === 'P'; fwrite($c, "200 ok\r\n"); break;
                case 'USER': fwrite($c, $arg === 'nobody' ? "530 not you\r\n" : "331 password\r\n"); break;
                case 'PASS': fwrite($c, $arg === 'wrong' ? "530 bad password\r\n" : "230 logged in\r\n"); break;
                case 'TYPE': fwrite($c, "200 type set\r\n"); break;
                case 'SIZE':
                    if (isset($files[$arg])) fwrite($c, "213 " . strlen($files[$arg]) . "\r\n");
                    else fwrite($c, "550 $arg: no such file\r\n");
                    break;
                case 'MDTM':
                    fwrite($c, isset($files[$arg]) ? "213 20240229123456\r\n" : "550 no\r\n");
                    break;
                case 'CWD': fwrite($c, in_array($arg, $dirs, true) ? "250 ok\r\n" : "550 not a directory\r\n"); break;
                case 'EPSV': fwrite($c, "229 Entering Extended Passive Mode (|||$data_port|)\r\n"); break;
                case 'RETR': case 'STOR': case 'APPE': case 'NLST':
                    if ($cmd === 'RETR' && !isset($files[$arg])) {
                        fwrite($c, "550 $arg: no such file\r\n");
                        break;
                    }
                    if ($cmd === 'NLST' && !in_array($arg, $dirs, true)) {
                        $d = stream_socket_accept($data_server, 5);
                        fclose($d);
                        fwrite($c, "550 $arg: No such file or directory\r\n");
                        break;
                    }
                    $d = stream_socket_accept($data_server, 5);
                    fwrite($c, "150 opening data connection\r\n");
                    if ($prot) {
                        stream_context_set_option($d, 'ssl', 'local_cert', "$dir/server.pem");
                        stream_socket_enable_crypto($d, true, STREAM_CRYPTO_METHOD_TLS_SERVER);
                    }
                    if ($cmd === 'RETR') {
                        fwrite($d, $files[$arg]);
                    } elseif ($cmd === 'NLST') {
                        foreach (array_keys($files) as $f) if (dirname($f) === $arg) fwrite($d, "$f\r\n");
                    } else {
                        $body = stream_get_contents($d);
                        $files[$arg] = $cmd === 'APPE' ? ($files[$arg] ?? '') . $body : $body;
                    }
                    fclose($d);
                    fwrite($c, "226 transfer complete\r\n");
                    break;
                case 'DELE':
                    if (isset($files[$arg])) {
                        unset($files[$arg]);
                        fwrite($c, "250 deleted\r\n");
                    } else fwrite($c, "550 $arg: cannot delete\r\n");
                    break;
                case 'RNFR':
                    $pending = $arg;
                    fwrite($c, isset($files[$arg]) ? "350 ready\r\n" : "550 $arg: no such file\r\n");
                    break;
                case 'RNTO':
                    $files[$arg] = $files[$pending];
                    unset($files[$pending]);
                    fwrite($c, "250 renamed\r\n");
                    break;
                case 'MKD':
                    if (in_array($arg, $dirs, true)) {
                        fwrite($c, "550 $arg: exists\r\n");
                    } else {
                        $dirs[] = $arg;
                        fwrite($c, "257 created\r\n");
                    }
                    break;
                case 'RMD':
                    $i = array_search($arg, $dirs, true);
                    if ($i === false) fwrite($c, "550 $arg: no such directory\r\n");
                    else {
                        unset($dirs[$i]);
                        fwrite($c, "250 removed\r\n");
                    }
                    break;
                case 'QUIT': fwrite($c, "221 bye\r\n"); break 2;
                default: fwrite($c, "502 not implemented\r\n");
            }
        }
        fclose($c);
    }
    exit(0);
}

function show_log(string $log): void
{
    // the client doesn't wait for the server to log a QUIT
    $seen = null;
    for ($i = 0; $i < 50; $i++) {
        usleep(20000);
        clearstatcache();
        $now = @file_get_contents($log) ?: '';
        if ($now === $seen) break;
        $seen = $now;
    }
    echo preg_replace('/\d{4,5}/', 'PORT', $seen), "--\n";
    @unlink($log);
}

[$port, $pid, $log] = ftp_server($dir, 30);
$base = "ftp://user:secret@127.0.0.1:$port";

echo "-- reading\n";
$f = fopen("$base/hello.txt", 'r');
var_dump(fread($f, 100));
$meta = stream_get_meta_data($f);
var_dump($meta['wrapper_type'], $meta['stream_type'], $meta['mode']);
var_dump(fclose($f));
show_log($log);
var_dump(file_get_contents("$base/hello.txt"));
show_log($log);

echo "-- missing files and bad logins\n";
var_dump(fopen("$base/missing.txt", 'r'));
show_log($log);
var_dump(fopen("ftp://nobody@127.0.0.1:$port/hello.txt", 'r'));
show_log($log);
var_dump(fopen("ftp://user:wrong@127.0.0.1:$port/hello.txt", 'r'));
show_log($log);
var_dump(fopen("$base/hello.txt", 'r+'));
var_dump(fopen("$base/hello.txt", 'x'));

echo "-- writing\n";
var_dump(file_put_contents("$base/new.txt", "written\n"));
show_log($log);
var_dump(file_put_contents("$base/new.txt", "again\n"));
show_log($log);
var_dump(file_put_contents("$base/new.txt", "again\n", false, stream_context_create(['ftp' => ['overwrite' => true]])));
$f = fopen("$base/new.txt", 'a');
fwrite($f, "appended\n");
fclose($f);
var_dump(file_get_contents("$base/new.txt"));
show_log($log);

echo "-- stat\n";
var_dump(filesize("$base/hello.txt"), filemtime("$base/hello.txt") === gmmktime(12, 34, 56, 2, 29, 2024));
var_dump(file_exists("$base/hello.txt"), is_file("$base/hello.txt"), is_dir("$base/dir"));
var_dump(file_exists("$base/nope"));
show_log($log);

echo "-- listings\n";
var_dump(scandir("$base/dir"));
$d = opendir("$base/dir");
var_dump(readdir($d), readdir($d), readdir($d));
closedir($d);
var_dump(opendir("$base/nodir"));
show_log($log);

echo "-- one-command operations\n";
var_dump(rename("$base/new.txt", "$base/renamed.txt"), rename("$base/gone.txt", "$base/x.txt"));
var_dump(rename("$base/renamed.txt", "ftp://127.0.0.2:$port/x.txt"), rename("$base/renamed.txt", __FILE__ . '.x'));
var_dump(unlink("$base/renamed.txt"), unlink("$base/renamed.txt"));
var_dump(mkdir("$base/dir"), mkdir("$base/dir/deep/er", 0777, true), rmdir("$base/dir/deep/er"), rmdir("$base/nodir"));
show_log($log);
pcntl_waitpid($pid, $status);

echo "-- ftps\n";
[$port, $pid, $log] = ftp_server($dir, 2);
$context = stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem", 'peer_name' => 'localhost']]);
var_dump(file_get_contents("FTPS://user:secret@127.0.0.1:$port/hello.txt", false, $context));
var_dump(scandir("ftps://user:secret@127.0.0.1:$port/dir", 0, $context));
pcntl_waitpid($pid, $status);
show_log($log);

echo "-- a server without ftps\n";
$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
[, $port] = explode(':', stream_socket_get_name($server, false));
$pid = pcntl_fork();
if ($pid === 0) {
    $c = stream_socket_accept($server, 10);
    fwrite($c, "220 ready\r\n");
    fgets($c);
    fwrite($c, "500 what\r\n");
    fgets($c);
    fwrite($c, "500 what\r\n");
    fgets($c);
    exit(0);
}
var_dump(fopen("ftps://127.0.0.1:$port/x", 'r'));
pcntl_waitpid($pid, $status);

echo "-- nothing listening\n";
$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
[, $port] = explode(':', stream_socket_get_name($server, false));
fclose($server);
var_dump(fopen("ftp://127.0.0.1:$port/x", 'r'), file_exists("ftp://127.0.0.1:$port/x"), unlink("ftp://127.0.0.1:$port/x"));
var_dump(in_array('ftp', stream_get_wrappers()), in_array('ftps', stream_get_wrappers()));
