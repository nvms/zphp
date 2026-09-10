<?php
$kind = $argv[1]; $data = file_get_contents($argv[2]);
switch ($kind) {
  case 'unserialize': @unserialize($data); @unserialize($data, ['allowed_classes' => false]); break;
  case 'json': @json_decode($data); @json_decode($data, true, 3); @json_encode($data); break;
  case 'unpack': foreach (['N*', 'C*', 'a*', 'H*', 'v2/n2/J', 'Z*x', 'q', 'e2E2', 'A3/h*'] as $f) { @unpack($f, $data); } @pack('A*', $data); @pack($data, 1, 2); break;
  case 'preg': @preg_match($data, "hello world 123"); @preg_match('/(\w+)\s+(?<n>\d+)/u', $data); @preg_replace('/x/', $data, $data); @preg_split($data, 'a,b'); @preg_quote($data); break;
  case 'xml': @simplexml_load_string($data); $d = new DOMDocument(); @$d->loadXML($data); @$d->loadHTML($data); $r = @XMLReader::fromString($data); if ($r) { while (@$r->read()) {} } @xml_parse(xml_parser_create(), $data, true); break;
  case 'utf8': @mb_strlen($data); @mb_substr($data, 1, 5); @mb_strtoupper($data); @mb_convert_encoding($data, 'UTF-16', 'UTF-8'); @mb_check_encoding($data); @iconv('UTF-8', 'ISO-8859-1//TRANSLIT', $data); @htmlspecialchars($data); @json_encode($data, JSON_INVALID_UTF8_SUBSTITUTE); @utf8_decode($data); @mb_str_split($data); @grapheme_strlen($data); @normalizer_normalize($data); break;
  case 'multipart': $b = "--b\r\nContent-Disposition: form-data; name=\"f\"; filename=\"x\"\r\n\r\n" . $data . "\r\n--b--\r\n"; break;
  case 'urls': @parse_url($data); @parse_str($data, $o); @urldecode($data); @base64_decode($data); @http_build_query([$data => $data]); @filter_var($data, FILTER_VALIDATE_URL); @strtotime($data); @date($data, 0); @sprintf($data, 1, 2.5, "s"); @sscanf($data, "%d %s"); @number_format(1234.5, 2, $data, $data); @str_word_count($data, 2); @strtr($data, $data, $data); @wordwrap($data, 3, $data, true); @similar_text($data, strrev($data)); @levenshtein($data, "abc"); @soundex($data); @metaphone($data); @crc32($data); @hash('sha3-256', $data); @gzdecode($data); @gzinflate($data); @bin2hex($data); @quoted_printable_decode($data); @convert_uuencode($data); @str_getcsv($data); @nl2br($data); @strip_tags($data); @html_entity_decode($data); @addcslashes($data, $data); @vsprintf($data, [1, 2]); @intdiv(PHP_INT_MIN, -1); break;
}
echo "ok";
