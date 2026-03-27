<?php
// covers: ord, chr, bin2hex, hex2bin, str_split, array_map, implode, sprintf, substr, strlen, str_pad, intval, dechex, base_convert

// --- hex encoding/decoding ---

function hexEncode(string $data): string {
    return bin2hex($data);
}

function hexDecode(string $hex): string {
    return hex2bin($hex);
}

$original = "Hello, World!";
$hex = hexEncode($original);
$decoded = hexDecode($hex);
echo "Original: $original\n";
echo "Hex: $hex\n";
echo "Decoded: $decoded\n";
echo "Match: " . ($original === $decoded ? "yes" : "no") . "\n";

// --- byte-level operations ---

echo "\nByte values of 'ABC':\n";
for ($i = 0; $i < strlen("ABC"); $i++) {
    $byte = ord("ABC"[$i]);
    echo "  " . "ABC"[$i] . " = $byte (0x" . str_pad(dechex($byte), 2, '0', STR_PAD_LEFT) . ")\n";
}

// --- build string from byte values ---

$bytes = [72, 101, 108, 108, 111];
$str = '';
foreach ($bytes as $b) {
    $str .= chr($b);
}
echo "\nFrom bytes: $str\n";

// --- simple checksum ---

function checksum(string $data): int {
    $sum = 0;
    for ($i = 0; $i < strlen($data); $i++) {
        $sum = ($sum + ord($data[$i])) % 256;
    }
    return $sum;
}

$msg = "test message";
$cs = checksum($msg);
echo "\nChecksum of '$msg': $cs\n";

// --- XOR cipher ---

function xorCipher(string $data, string $key): string {
    $result = '';
    $keyLen = strlen($key);
    for ($i = 0; $i < strlen($data); $i++) {
        $result .= chr(ord($data[$i]) ^ ord($key[$i % $keyLen]));
    }
    return $result;
}

$plaintext = "secret data";
$key = "mykey";
$encrypted = xorCipher($plaintext, $key);
$decrypted = xorCipher($encrypted, $key);
echo "\nPlaintext: $plaintext\n";
echo "Encrypted (hex): " . bin2hex($encrypted) . "\n";
echo "Decrypted: $decrypted\n";

// --- base conversion ---

echo "\nBase conversions:\n";
echo "  255 in hex: " . dechex(255) . "\n";
echo "  255 in binary: " . decbin(255) . "\n";
echo "  255 in octal: " . decoct(255) . "\n";
echo "  ff from hex: " . hexdec('ff') . "\n";
echo "  11111111 from bin: " . bindec('11111111') . "\n";
echo "  377 from octal: " . octdec('377') . "\n";
echo "  base 16 to base 2: " . base_convert('ff', 16, 2) . "\n";

// --- bit manipulation via string ---

function getBit(int $byte, int $pos): int {
    return ($byte >> $pos) & 1;
}

function setBit(int $byte, int $pos): int {
    return $byte | (1 << $pos);
}

function clearBit(int $byte, int $pos): int {
    return $byte & ~(1 << $pos);
}

$val = 0b10110100;
echo "\nBit operations on " . decbin($val) . " ($val):\n";
echo "  bit 2: " . getBit($val, 2) . "\n";
echo "  bit 3: " . getBit($val, 3) . "\n";
echo "  set bit 0: " . decbin(setBit($val, 0)) . "\n";
echo "  clear bit 4: " . decbin(clearBit($val, 4)) . "\n";

// --- simple TLV (type-length-value) encoding ---

function tlvEncode(int $type, string $value): string {
    $len = strlen($value);
    return chr($type) . chr($len) . $value;
}

function tlvDecode(string $data): array {
    $result = [];
    $pos = 0;
    while ($pos < strlen($data)) {
        $type = ord($data[$pos]);
        $len = ord($data[$pos + 1]);
        $value = substr($data, $pos + 2, $len);
        $result[] = ['type' => $type, 'length' => $len, 'value' => $value];
        $pos += 2 + $len;
    }
    return $result;
}

$packet = tlvEncode(1, "hello") . tlvEncode(2, "world") . tlvEncode(3, "!");
$fields = tlvDecode($packet);

echo "\nTLV packet (hex): " . bin2hex($packet) . "\n";
echo "Decoded fields:\n";
foreach ($fields as $f) {
    echo "  type=" . $f['type'] . " len=" . $f['length'] . " value=\"" . $f['value'] . "\"\n";
}

// --- hex dump ---

function hexDump(string $data, int $width = 16): string {
    $lines = [];
    $len = strlen($data);
    for ($offset = 0; $offset < $len; $offset += $width) {
        $chunk = substr($data, $offset, $width);
        $hex_parts = [];
        $ascii = '';
        for ($i = 0; $i < strlen($chunk); $i++) {
            $byte = ord($chunk[$i]);
            $hex_parts[] = str_pad(dechex($byte), 2, '0', STR_PAD_LEFT);
            $ascii .= ($byte >= 32 && $byte < 127) ? $chunk[$i] : '.';
        }
        $hex_str = implode(' ', $hex_parts);
        $hex_str = str_pad($hex_str, $width * 3 - 1);
        $lines[] = sprintf("%04x  %s  |%s|", $offset, $hex_str, $ascii);
    }
    return implode("\n", $lines);
}

echo "\nHex dump of 'Hello, World!123':\n";
echo hexDump("Hello, World!123") . "\n";

// --- ROT13 via ord/chr ---

function rot13Manual(string $str): string {
    $result = '';
    for ($i = 0; $i < strlen($str); $i++) {
        $c = ord($str[$i]);
        if ($c >= 65 && $c <= 90) {
            $c = (($c - 65 + 13) % 26) + 65;
        } elseif ($c >= 97 && $c <= 122) {
            $c = (($c - 97 + 13) % 26) + 97;
        }
        $result .= chr($c);
    }
    return $result;
}

$text = "Hello World";
$rotated = rot13Manual($text);
$back = rot13Manual($rotated);
echo "\nROT13: $text -> $rotated -> $back\n";
echo "Matches str_rot13: " . (str_rot13($text) === $rotated ? "yes" : "no") . "\n";
