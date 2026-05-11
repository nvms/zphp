<?php
// covers: posix_getuid, posix_getgid, posix_getpwuid, posix_getgrgid,
//   posix_getpid, posix_getppid, posix_geteuid, posix_strerror,
//   array_diff_key, str_pad, sprintf, fprintf, type checks

function summary(array $a, array $keys): array {
    $out = [];
    foreach ($keys as $k) {
        $out[$k] = $a[$k] ?? null;
    }
    return $out;
}

echo "=== process identity ===\n";
echo "pid is positive: " . (posix_getpid() > 0 ? "yes" : "no") . "\n";
echo "ppid is positive: " . (posix_getppid() > 0 ? "yes" : "no") . "\n";
echo "uid type: " . (is_int(posix_getuid()) ? "int" : "wrong") . "\n";
echo "euid == uid for this script: " . (posix_geteuid() === posix_getuid() ? "yes" : "no") . "\n";

echo "\n=== user lookup ===\n";
$pw = posix_getpwuid(posix_getuid());
if ($pw !== false) {
    $shape = summary($pw, ['uid', 'gid', 'name']);
    echo "uid matches: " . ($shape['uid'] === posix_getuid() ? "yes" : "no") . "\n";
    echo "gid matches: " . ($shape['gid'] === posix_getgid() ? "yes" : "no") . "\n";
    echo "name is string: " . (is_string($shape['name']) ? "yes" : "no") . "\n";
    echo "name non-empty: " . (strlen($shape['name']) > 0 ? "yes" : "no") . "\n";
}

echo "\n=== group lookup ===\n";
$gr = posix_getgrgid(posix_getgid());
if ($gr !== false) {
    echo "gid matches: " . ($gr['gid'] === posix_getgid() ? "yes" : "no") . "\n";
    echo "name is string: " . (is_string($gr['name']) ? "yes" : "no") . "\n";
}

echo "\n=== errno strings ===\n";
$errnos = [0, 1, 2, 22];
foreach ($errnos as $n) {
    $s = posix_strerror($n);
    echo sprintf("  errno %2d: %s\n", $n, is_string($s) ? "string" : gettype($s));
}

echo "\n=== signal constants are stable integers ===\n";
$sigs = ['SIGTERM' => SIGTERM, 'SIGINT' => SIGINT, 'SIGUSR1' => SIGUSR1, 'SIGKILL' => SIGKILL];
foreach ($sigs as $name => $val) {
    echo sprintf("  %-10s = %d (int=%s)\n", $name, $val, is_int($val) ? "yes" : "no");
}
echo "SIGTERM != SIGKILL: " . (SIGTERM !== SIGKILL ? "yes" : "no") . "\n";
echo "SIG_DFL == 0: " . (SIG_DFL === 0 ? "yes" : "no") . "\n";

echo "\n=== rlimit dictionary shape ===\n";
$lim = posix_getrlimit() ?: [];
$has_keys = isset($lim['soft openfiles']) && isset($lim['hard openfiles']);
echo "has soft/hard openfiles: " . ($has_keys ? "yes" : "no") . "\n";
