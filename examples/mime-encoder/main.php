<?php
// covers: base64_encode, base64_decode, wordwrap, str_word_count, array_combine, array_flip, array_pad, chunk_split, quoted_printable_encode, quoted_printable_decode, str_split, implode, explode, strtolower, strtoupper, substr, strlen, str_replace, trim, rtrim, sprintf, array_map, array_keys, array_values, array_merge, in_array, preg_match, ord

// --- base64 encoding/decoding ---

echo "Base64 encoding:\n";
$text = "Hello, World!";
$encoded = base64_encode($text);
echo "Original: $text\n";
echo "Encoded: $encoded\n";
$decoded = base64_decode($encoded);
echo "Decoded: $decoded\n";
echo "Match: " . ($text === $decoded ? "yes" : "no") . "\n";

// binary data
$binary = "";
for ($i = 0; $i < 256; $i++) {
    $binary .= chr($i);
}
$b64 = base64_encode($binary);
$back = base64_decode($b64);
echo "Binary round-trip (256 bytes): " . (strlen($back) === 256 ? "ok" : "fail") . "\n";

// empty string
echo "Empty base64: '" . base64_encode("") . "'\n";
echo "Empty decode: '" . base64_decode("") . "'\n";

// padding cases
echo "\nBase64 padding:\n";
echo "1 byte: " . base64_encode("A") . "\n";
echo "2 bytes: " . base64_encode("AB") . "\n";
echo "3 bytes: " . base64_encode("ABC") . "\n";
echo "4 bytes: " . base64_encode("ABCD") . "\n";

// --- wordwrap ---

echo "\nWordwrap:\n";
$long = "The quick brown fox jumped over the lazy dog on a sunny afternoon";
echo wordwrap($long, 20, "\n", false) . "\n";
echo "---\n";
echo wordwrap($long, 20, "\n", true) . "\n";
echo "---\n";

// single long word with cut
echo wordwrap("Supercalifragilisticexpialidocious", 10, "\n", true) . "\n";
echo "---\n";

// custom break
echo wordwrap("one two three four five", 10, "<br>", false) . "\n";

// --- str_word_count ---

echo "\nWord count:\n";
$sentence = "Hello beautiful world";
echo "Words in '$sentence': " . str_word_count($sentence) . "\n";

$complex = "  spaces   between   words  ";
echo "Words with extra spaces: " . str_word_count($complex) . "\n";

echo "Empty string: " . str_word_count("") . "\n";
echo "Single word: " . str_word_count("hello") . "\n";

// mode 1: return array of words
$words = str_word_count("The quick brown fox", 1);
echo "Word list: " . implode(", ", $words) . "\n";

// mode 2: return positions
$positions = str_word_count("Hello world test", 2);
foreach ($positions as $pos => $word) {
    echo "  Position $pos: $word\n";
}

// --- array_combine ---

echo "\nArray combine:\n";
$keys = ['name', 'age', 'city'];
$values = ['Alice', 30, 'NYC'];
$combined = array_combine($keys, $values);
foreach ($combined as $k => $v) {
    echo "  $k: $v\n";
}

// --- array_flip ---

echo "\nArray flip:\n";
$colors = ['red' => 1, 'green' => 2, 'blue' => 3];
$flipped = array_flip($colors);
foreach ($flipped as $k => $v) {
    echo "  $k => $v\n";
}

// flip indexed array
$fruits = ['apple', 'banana', 'cherry'];
$fruit_index = array_flip($fruits);
echo "Index of banana: " . $fruit_index['banana'] . "\n";

// --- array_pad ---

echo "\nArray pad:\n";
$arr = [1, 2, 3];
$padded_right = array_pad($arr, 6, 0);
echo "Pad right to 6: " . implode(",", $padded_right) . "\n";

$padded_left = array_pad($arr, -6, 0);
echo "Pad left to -6: " . implode(",", $padded_left) . "\n";

$no_pad = array_pad($arr, 2, 0);
echo "Pad to 2 (no change): " . implode(",", $no_pad) . "\n";

// --- MIME header encoding ---

echo "\nMIME header encoding:\n";

function encodeHeader(string $name, string $value, string $charset = 'UTF-8'): string {
    $needs_encoding = false;
    for ($i = 0; $i < strlen($value); $i++) {
        if (ord($value[$i]) > 127 || ord($value[$i]) < 32) {
            $needs_encoding = true;
            break;
        }
    }

    if (!$needs_encoding) {
        return "$name: $value";
    }

    $encoded = base64_encode($value);
    return "$name: =?" . strtoupper($charset) . "?B?" . $encoded . "?=";
}

echo encodeHeader("Subject", "Hello World") . "\n";
echo encodeHeader("Subject", "Test with special: " . chr(200) . chr(201)) . "\n";

// --- MIME multipart message builder ---

echo "\nMIME multipart message:\n";

function buildMimeMessage(array $parts): string {
    $boundary = "----boundary_12345";
    $lines = [];
    $lines[] = "MIME-Version: 1.0";
    $lines[] = "Content-Type: multipart/mixed; boundary=\"$boundary\"";
    $lines[] = "";
    $lines[] = "This is a multi-part message in MIME format.";

    foreach ($parts as $part) {
        $lines[] = "";
        $lines[] = "--$boundary";

        $type = $part['type'] ?? 'text/plain';
        $encoding = $part['encoding'] ?? '7bit';
        $lines[] = "Content-Type: $type";
        $lines[] = "Content-Transfer-Encoding: $encoding";

        if (isset($part['filename'])) {
            $lines[] = "Content-Disposition: attachment; filename=\"" . $part['filename'] . "\"";
        }

        $lines[] = "";

        if ($encoding === 'base64') {
            $encoded = base64_encode($part['body']);
            $wrapped = wordwrap($encoded, 76, "\n", true);
            $lines[] = $wrapped;
        } else {
            $lines[] = $part['body'];
        }
    }

    $lines[] = "";
    $lines[] = "--$boundary--";

    return implode("\r\n", $lines);
}

$message = buildMimeMessage([
    [
        'type' => 'text/plain; charset=UTF-8',
        'encoding' => '7bit',
        'body' => 'Hello, this is the plain text body of the email.',
    ],
    [
        'type' => 'application/octet-stream',
        'encoding' => 'base64',
        'filename' => 'data.bin',
        'body' => "Binary content: " . chr(0) . chr(255) . chr(128) . chr(64),
    ],
]);

$msg_lines = explode("\r\n", $message);
echo "Lines: " . count($msg_lines) . "\n";
echo "Has MIME-Version: " . (str_contains($message, "MIME-Version: 1.0") ? "yes" : "no") . "\n";
echo "Has boundary: " . (str_contains($message, "----boundary_12345") ? "yes" : "no") . "\n";
echo "Has base64: " . (str_contains($message, "Content-Transfer-Encoding: base64") ? "yes" : "no") . "\n";

// decode the attachment back
preg_match('/Content-Transfer-Encoding: base64\r\n.+?\r\n\r\n(.+?)(?:\r\n\r\n--|\z)/s', $message, $matches);
if (isset($matches[1])) {
    $decoded_attachment = base64_decode(trim($matches[1]));
    echo "Attachment decoded length: " . strlen($decoded_attachment) . "\n";
    echo "Attachment starts with 'Binary content: ': " . (str_starts_with($decoded_attachment, "Binary content: ") ? "yes" : "no") . "\n";
}

// --- content type parser using array_combine ---

echo "\nContent-Type parser:\n";

function parseContentType(string $header): array {
    $parts = explode(';', $header);
    $type = trim($parts[0]);
    $params = [];

    for ($i = 1; $i < count($parts); $i++) {
        $kv = explode('=', trim($parts[$i]), 2);
        if (count($kv) === 2) {
            $key = trim(strtolower($kv[0]));
            $val = trim($kv[1], ' "');
            $params[$key] = $val;
        }
    }

    return array_merge(['type' => $type], $params);
}

$ct = parseContentType('text/html; charset="UTF-8"; boundary=something');
echo "Type: " . $ct['type'] . "\n";
echo "Charset: " . $ct['charset'] . "\n";
echo "Boundary: " . $ct['boundary'] . "\n";

// --- lookup table with array_flip ---

echo "\nMIME type lookup:\n";

$mime_types = [
    'txt' => 'text/plain',
    'html' => 'text/html',
    'css' => 'text/css',
    'js' => 'application/javascript',
    'json' => 'application/json',
    'png' => 'image/png',
    'jpg' => 'image/jpeg',
    'gif' => 'image/gif',
    'pdf' => 'application/pdf',
];

$ext_lookup = array_flip($mime_types);

echo "Extension for text/html: " . $ext_lookup['text/html'] . "\n";
echo "Extension for image/png: " . $ext_lookup['image/png'] . "\n";
echo "MIME for json: " . $mime_types['json'] . "\n";

// --- header table with array_pad ---

echo "\nHeader alignment:\n";

function formatTable(array $rows, int $cols): void {
    foreach ($rows as $row) {
        $padded = array_pad($row, $cols, '');
        $formatted = array_map(function($v) { return str_pad((string)$v, 15); }, $padded);
        echo implode(" | ", $formatted) . "\n";
    }
}

formatTable([
    ['Name', 'Value'],
    ['Content-Type', 'text/plain'],
    ['Encoding', 'base64'],
    ['Size'],
], 2);

// --- word frequency analysis ---

echo "\nWord frequency:\n";
$text = "the cat sat on the mat the cat";
$words = str_word_count(strtolower($text), 1);
$freq = [];
foreach ($words as $w) {
    if (!isset($freq[$w])) $freq[$w] = 0;
    $freq[$w]++;
}
arsort($freq);
foreach ($freq as $word => $count) {
    echo "  $word: $count\n";
}
