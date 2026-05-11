<?php
// covers: ftp_* constants and error paths (no live server required)

assert(FTP_ASCII === 1);
assert(FTP_TEXT === 1);
assert(FTP_BINARY === 2);
assert(FTP_IMAGE === 2);
assert(defined('FTP_AUTOSEEK'));
assert(defined('FTP_TIMEOUT_SEC'));
assert(defined('FTP_USEPASVADDRESS'));

// connect to a port that should not be listening locally
$f = @ftp_connect('127.0.0.1', 1);
assert($f === false);

echo "ok\n";
