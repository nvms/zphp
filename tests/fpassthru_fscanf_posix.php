<?php
// fpassthru
$fh = fopen('php://memory', 'w+');
fwrite($fh, "Hello, World!\n");
rewind($fh);
$ret = fpassthru($fh);
echo "ret:$ret\n";
fclose($fh);

// fscanf
$fh = fopen('php://memory', 'w+');
fwrite($fh, "alice 30\nbob 25\n");
rewind($fh);
$r = fscanf($fh, "%s %d");
print_r($r);
$r = fscanf($fh, "%s %d");
print_r($r);
fclose($fh);

// fscanf single value
$fh = fopen('php://memory', 'w+');
fwrite($fh, "3.14\n");
rewind($fh);
$r = fscanf($fh, "%f");
print_r($r);
fclose($fh);

// getrusage returns array
$r = getrusage();
var_dump(is_array($r));
echo array_key_exists('ru_utime.tv_sec', $r) ? "has utime\n" : "no utime\n";

// posix_getpid/getuid/getgid exist and return int
var_dump(is_int(posix_getpid()));
var_dump(is_int(posix_getuid()));
var_dump(is_int(posix_geteuid()));
var_dump(is_int(posix_getgid()));
var_dump(is_int(posix_getegid()));
var_dump(posix_getpid() > 0);

// sprintf with positional + flags
echo sprintf('%1$+d %2$05d', 5, 7), "\n";
echo sprintf('%1$-10s|%2$10s', 'a', 'b'), "\n";

// ucwords default + custom
echo ucwords("hello world"), "\n";
echo ucwords("a-b_c d", "-_ "), "\n";

// str_word_count
echo str_word_count("hello world"), "\n";
print_r(str_word_count("hello world foo", 1));
print_r(str_word_count("hello world foo", 2));

// array_search NaN never matches
var_dump(array_search(NAN, [1, 2, NAN, 3]));
var_dump(in_array(NAN, [1, 2, NAN, 3]));

// escapeshellarg
echo escapeshellarg("hello world"), "\n";
echo escapeshellarg("hello'world"), "\n";
