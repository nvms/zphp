<?php
// covers: posix_getpid, posix_getppid, posix_getuid, posix_geteuid, posix_getgid, posix_getegid, posix_isatty, posix_kill, posix_getpwuid, posix_getgrgid, posix_strerror, posix_uname

assert(is_int(posix_getpid()) && posix_getpid() > 0);
assert(is_int(posix_getppid()) && posix_getppid() > 0);
assert(is_int(posix_getuid()) && posix_getuid() >= 0);
assert(posix_geteuid() === posix_geteuid());
assert(is_int(posix_getgid()) && posix_getgid() >= 0);
assert(is_int(posix_getegid()) && posix_getegid() >= 0);

// isatty against an obviously non-tty fd (we don't know stream resources here, just int)
$res = posix_isatty(999);
assert($res === false || $res === true);

// kill with signal 0 just checks process exists
$ok = posix_kill(posix_getpid(), 0);
assert($ok === true);

// pwuid for current uid
$pw = posix_getpwuid(posix_getuid());
assert(is_array($pw));
assert(isset($pw['uid']));
assert($pw['uid'] === posix_getuid());

// grgid for current gid
$gr = posix_getgrgid(posix_getgid());
assert(is_array($gr));
assert($gr['gid'] === posix_getgid());

// strerror
$s = posix_strerror(2);
assert(is_string($s) && strlen($s) > 0);

// uname returns array shape
$u = posix_uname();
assert(is_array($u));
assert(array_key_exists('sysname', $u));

echo "ok\n";
