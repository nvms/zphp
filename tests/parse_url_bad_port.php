<?php
// regression: parse_url returns false when the port component is
// non-numeric or out of the 0-65535 range. previously zphp left port=null
// and returned the otherwise-parsed array
var_dump(parse_url('http://example.com:bad/path'));
var_dump(parse_url('http://example.com:99999/'));
var_dump(parse_url('http://example.com:-1/'));
var_dump(parse_url('http://[::1]:bad/'));

// valid port edges
$u = parse_url('http://example.com:0');
echo $u['port'] . "\n";
$u = parse_url('http://example.com:65535');
echo $u['port'] . "\n";

// no port specified - unchanged
$u = parse_url('http://example.com');
var_dump(isset($u['port']));
