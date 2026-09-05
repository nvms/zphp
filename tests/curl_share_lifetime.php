<?php
function handles() {
    $s = curl_share_init();
    curl_share_setopt($s, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);
    $a = curl_init(); $b = curl_init();
    curl_setopt($a, CURLOPT_SHARE, $s);
    curl_setopt($a, CURLOPT_SHARE, $s); // same-share replacement balances ownership
    curl_setopt($b, CURLOPT_SHARE, $s);
    curl_setopt($a, CURLOPT_COOKIELIST, "example.test\tFALSE\t/\tFALSE\t0\tkey\tvalue");
    return [$a, $b];
}
for ($i = 0; $i < 100; $i++) {
    $pair = handles();
    $a = $pair[0]; $b = $pair[1];
    unset($pair);
    unset($a);
    curl_reset($b);
    if (count(curl_getinfo($b, CURLINFO_COOKIELIST)) !== 1) echo "lost cookie\n";
    unset($b);
}
echo "lifetime ok\n";
try { new CurlShareHandle(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
// Easy allocated before share tests the reverse request-sweep order.
$a = curl_init(); $s = curl_share_init();
curl_share_setopt($s, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);
curl_setopt($a, CURLOPT_SHARE, $s);
echo "done\n";
