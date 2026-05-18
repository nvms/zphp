<?php
// regression: md5_file and sha1_file - convenience aliases for hash_file
// with the algo baked in. previously missing; calls raised 'undefined
// function' even though hash_file('md5', $path) was available
$tmp = tempnam(sys_get_temp_dir(), 'zphp_hf_');
file_put_contents($tmp, "hello world\n");

echo md5_file($tmp) . "\n";
echo sha1_file($tmp) . "\n";
echo bin2hex(md5_file($tmp, true)) . "\n";
echo bin2hex(sha1_file($tmp, true)) . "\n";

// match against the buffer hash
echo (md5_file($tmp) === md5(file_get_contents($tmp)) ? 'y' : 'n') . "\n";
echo (sha1_file($tmp) === sha1(file_get_contents($tmp)) ? 'y' : 'n') . "\n";

// missing file returns false
var_dump(md5_file('/nonexistent/path/that/does/not/exist'));
var_dump(sha1_file('/nonexistent/path/that/does/not/exist'));

unlink($tmp);
