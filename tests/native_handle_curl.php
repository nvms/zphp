<?php
$ch = curl_init("http://127.0.0.1:9/original");
var_dump(isset($ch->__curl_ptr), isset($ch->__slist_ptr), isset($ch->__share_state));
var_dump(curl_setopt($ch, CURLOPT_HTTPHEADER, ["X-One: 1"]));
var_dump(curl_getinfo($ch, CURLINFO_EFFECTIVE_URL));

$copy = clone $ch;
var_dump($copy instanceof CurlHandle);
var_dump($copy !== $ch);
var_dump(curl_getinfo($copy, CURLINFO_EFFECTIVE_URL));
var_dump(curl_setopt($copy, CURLOPT_URL, "http://127.0.0.1:9/copy"));
var_dump(curl_getinfo($copy, CURLINFO_EFFECTIVE_URL));
var_dump(curl_getinfo($ch, CURLINFO_EFFECTIVE_URL));
var_dump(curl_setopt($copy, CURLOPT_HTTPHEADER, ["X-Two: 2"]));
var_dump(curl_setopt($ch, CURLOPT_HTTPHEADER, ["X-Three: 3"]));
var_dump(curl_errno($copy));
curl_close($copy);
curl_close($ch);

$sh = curl_share_init();
var_dump(isset($sh->__share_state));
var_dump(curl_share_setopt($sh, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE));
var_dump(curl_share_errno($sh));
try {
    $x = clone $sh;
    echo "unexpected clone\n";
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump(curl_share_errno($sh));

$mh = curl_multi_init();
var_dump(isset($mh->__multi_ptr));
$e1 = curl_init("http://127.0.0.1:9/a");
var_dump(curl_multi_add_handle($mh, $e1));
var_dump(curl_multi_remove_handle($mh, $e1));
try {
    $y = clone $mh;
    echo "unexpected clone\n";
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
curl_multi_close($mh);
echo "done\n";
