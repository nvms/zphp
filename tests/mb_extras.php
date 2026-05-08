<?php
// mb_chr / mb_ord
echo mb_chr(0x1F600), "\n";
echo mb_chr(0x4E2D), "\n";
echo mb_chr(233), "\n";
echo mb_ord("é"), "\n";
echo mb_ord("中"), "\n";
echo mb_ord("a"), "\n";

// mb_stripos
echo mb_stripos("Héllo Wörld", "WÖR"), "\n";
echo mb_stripos("Héllo Wörld", "héllo"), "\n";
var_dump(mb_stripos("Héllo", "Z"));
echo mb_stripos("ABCabc", "b", 2), "\n";

// mb_strstr / mb_stristr
echo mb_strstr("Héllo Wörld", "Wö"), "\n";
echo mb_stristr("Héllo Wörld", "wö"), "\n";
echo mb_strstr("Héllo Wörld", "Wö", true), "\n";
echo mb_stristr("Héllo Wörld", "wö", true), "\n";
var_dump(mb_strstr("hi", "x"));

// mb_strcut byte-based
$s = "héllo wörld";
echo mb_strcut($s, 0, 6), "\n"; // first 6 bytes, char-aligned
echo mb_strcut($s, 7), "\n";

// mb_str_pad
echo mb_str_pad("日", 5, "・"), "\n";
echo mb_str_pad("日", 5, "・", STR_PAD_LEFT), "\n";
echo mb_str_pad("日", 5, "・", STR_PAD_BOTH), "\n";
echo mb_str_pad("hi", 6, "ab", STR_PAD_BOTH), "\n";
echo mb_strlen(mb_str_pad("日", 5, "・")), "\n";
