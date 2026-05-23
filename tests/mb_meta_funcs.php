<?php
// mb_strrichr, mb_scrub, mb_http_input/output, mb_language,
// mb_preferred_mime_name, mb_detect_order, mb_get_info, mb_parse_str
echo "== mb_strrichr ==\n";
var_dump(mb_strrichr("Line1\nLINE2\nline3", "L"));
var_dump(mb_strrichr("Line1\nLINE2\nline3", "L", true));
var_dump(mb_strrichr("none here", "Z"));

echo "== mb_get_info (clean) ==\n";
print_r(mb_get_info());

echo "== mb_scrub ==\n";
var_dump(mb_scrub("\xff\xfeABC"));
var_dump(mb_scrub("hello"));
var_dump(mb_scrub("café"));

echo "== mb_http_input / mb_http_output / mb_language ==\n";
var_dump(mb_http_input());
var_dump(mb_http_output());
var_dump(mb_language());

echo "== mb_preferred_mime_name ==\n";
var_dump(mb_preferred_mime_name("UTF-8"));
var_dump(mb_preferred_mime_name("ISO-8859-1"));
var_dump(mb_preferred_mime_name("SJIS"));
var_dump(mb_preferred_mime_name("ASCII"));
var_dump(mb_preferred_mime_name("EUC-JP"));
try {
    mb_preferred_mime_name("UNKNOWN-ENC");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}

echo "== mb_detect_order ==\n";
print_r(mb_detect_order());
var_dump(mb_detect_order("ASCII,UTF-8"));

echo "== mb_get_info (keys) ==\n";
var_dump(mb_get_info("internal_encoding"));
var_dump(mb_get_info("language"));
var_dump(mb_get_info("substitute_character"));

echo "== mb_parse_str ==\n";
$out = [];
mb_parse_str("a=1&b=hi&list[]=x&list[]=y&nested[k]=v", $out);
print_r($out);
