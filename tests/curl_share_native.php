<?php
// No sockets: libcurl's cookie-list API proves actual cross-handle state.
$s = curl_share_init();
var_dump(get_class($s), curl_share_errno($s));
var_dump(curl_share_setopt($s, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE));
var_dump(curl_share_setopt($s, CURLSHOPT_SHARE, 99999), curl_share_errno($s));
try { curl_share_setopt($s, 99999, 2); } catch (ValueError $e) { echo $e->getMessage(), "\n"; }
var_dump(curl_share_errno($s));
var_dump(curl_share_setopt($s, CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS), curl_share_errno($s));
$a = curl_init(); $b = curl_init();
var_dump(curl_setopt($a, CURLOPT_SHARE, $s), curl_setopt_array($b, [CURLOPT_SHARE => $s]));
var_dump(curl_share_setopt($s, CURLSHOPT_UNSHARE, CURL_LOCK_DATA_COOKIE), curl_share_errno($s));
var_dump(curl_share_close($s));
var_dump(curl_setopt($a, CURLOPT_COOKIELIST, "example.test\tFALSE\t/\tFALSE\t0\tshared\tyes"));
var_dump(curl_getinfo($b, CURLINFO_COOKIELIST));
curl_reset($b);
var_dump(curl_getinfo($b, CURLINFO_COOKIELIST));
// PHP ignores null rather than detaching the share.
var_dump(curl_setopt($b, CURLOPT_SHARE, null));
var_dump(curl_getinfo($b, CURLINFO_COOKIELIST));
$s2 = curl_share_init();
curl_share_setopt($s2, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);
var_dump(curl_setopt($b, CURLOPT_SHARE, $s2));
var_dump(curl_getinfo($b, CURLINFO_COOKIELIST));
unset($s, $s2);
var_dump(curl_getinfo($a, CURLINFO_COOKIELIST));
curl_setopt($b, CURLOPT_COOKIELIST, "example.test\tFALSE\t/\tFALSE\t0\tother\tok");
var_dump(curl_getinfo($b, CURLINFO_COOKIELIST));
unset($a, $b);
foreach ([0, 1, 2, 3, 4, 5, -1, 99999] as $code) { var_dump(curl_share_strerror($code)); }
$s = curl_share_init();
var_dump(curl_share_setopt($s, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE));
var_dump(curl_share_setopt($s, CURLSHOPT_UNSHARE, CURL_LOCK_DATA_COOKIE));
var_dump(curl_share_errno($s));
// Leave wrappers and associated native resources for the request sweep.
$a = curl_init(); curl_setopt($a, CURLOPT_SHARE, $s);
echo "done\n";
