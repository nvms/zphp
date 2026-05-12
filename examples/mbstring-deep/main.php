<?php
// covers: mb_strlen vs strlen, mb_substr, mb_str_split, mb_convert_case,
//   mb_strpos / mb_stripos, mb_strtolower/upper, mb_convert_encoding,
//   mb_check_encoding, mb_detect_encoding

echo "=== byte vs char length ===\n";
$s = "Héllo Wörld 世界";
echo "strlen (bytes): " . strlen($s) . "\n";
echo "mb_strlen (chars): " . mb_strlen($s) . "\n";

echo "\n=== mb_substr handles multibyte ===\n";
$s = "café résumé 世界";
echo "first 5 chars: [" . mb_substr($s, 0, 5) . "]\n";
echo "skip 5: [" . mb_substr($s, 5) . "]\n";
echo "last 2: [" . mb_substr($s, -2) . "]\n";

echo "\n=== mb_str_split ===\n";
$pieces = mb_str_split("世界café", 1);
echo "char-by-char: " . implode(' | ', $pieces) . " (" . count($pieces) . " chars)\n";

$pairs = mb_str_split("abcdef世界", 2);
echo "by pairs: " . implode(' | ', $pairs) . "\n";

echo "\n=== mb_convert_case ===\n";
echo "upper: " . mb_convert_case("café Résumé", MB_CASE_UPPER) . "\n";
echo "lower: " . mb_convert_case("CAFÉ RÉSUMÉ", MB_CASE_LOWER) . "\n";
echo "title: " . mb_convert_case("café résumé works", MB_CASE_TITLE) . "\n";

echo "\n=== mb_strtolower / mb_strtoupper ===\n";
echo "lower: " . mb_strtolower("CAFÉ RÉSUMÉ") . "\n";
echo "upper: " . mb_strtoupper("café résumé") . "\n";

echo "\n=== mb_strpos / mb_stripos ===\n";
$haystack = "café résumé café";
echo "first café: " . mb_strpos($haystack, 'café') . "\n";
echo "second café: " . mb_strpos($haystack, 'café', 1) . "\n";
echo "case-insensitive (CAFÉ): " . mb_stripos($haystack, 'CAFÉ') . "\n";
echo "missing: " . var_export(mb_strpos($haystack, 'pizza'), true) . "\n";

echo "\n=== mb_check_encoding ===\n";
echo "ascii ok as UTF-8: " . (mb_check_encoding("hello", 'UTF-8') ? "yes" : "no") . "\n";
echo "utf-8 ok: " . (mb_check_encoding("café", 'UTF-8') ? "yes" : "no") . "\n";
echo "invalid utf-8: " . (mb_check_encoding("\xff\xfe\xfd", 'UTF-8') ? "yes" : "no") . "\n";

echo "\n=== mb_detect_encoding ===\n";
$enc1 = mb_detect_encoding("plain ascii", ['UTF-8', 'ASCII']);
$enc2 = mb_detect_encoding("café", ['UTF-8', 'ASCII']);
echo "ascii input: $enc1\n";
echo "utf-8 input: $enc2\n";

echo "\n=== mb_convert_encoding ===\n";
$utf8 = "Héllo";
$latin = mb_convert_encoding($utf8, 'ISO-8859-1', 'UTF-8');
echo "utf-8 to latin1 bytes: " . bin2hex($latin) . "\n";
$back = mb_convert_encoding($latin, 'UTF-8', 'ISO-8859-1');
echo "round trip: " . ($back === $utf8 ? "yes" : "no") . "\n";

echo "\n=== mb_internal_encoding ===\n";
$prev = mb_internal_encoding();
echo "default: $prev\n";
mb_internal_encoding('UTF-8');
echo "set ok: " . mb_internal_encoding() . "\n";

echo "\n=== mb_str_pad ===\n";
echo "[" . mb_str_pad("世界", 10, '_', STR_PAD_BOTH) . "]\n";

echo "\n=== preg matches by char position vs byte position ===\n";
$text = "世café界";
echo "char count: " . mb_strlen($text) . " bytes: " . strlen($text) . "\n";

echo "\n=== count multibyte words ===\n";
$paragraph = "café résumé naïve façade jalapeño";
$word_count = preg_match_all('/[\p{L}\p{N}]+/u', $paragraph);
echo "unicode word count: $word_count\n";

echo "\n=== chunk text by char count ===\n";
$rows = mb_str_split("世界café résumé naïve", 4);
foreach ($rows as $r) echo "  [$r]\n";

echo "\ndone\n";
