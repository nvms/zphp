<?php
// getimagesize and getimagesizefromstring read each format's header as
// php's image.c does
$images = [
    'gif' => "GIF89a" . pack('vv', 31, 17) . "\xf7\x00\x00",
    'png' => "\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR" . pack('NN', 640, 480) . "\x08\x06\x00\x00\x00",
    'png ascii' => "\x89PNG\n\x1a\n\x00\x00\x00\x0dIHDR",
    'bmp' => "BM" . str_repeat("\0", 12) . pack('VVVvv', 40, 100, -50, 1, 24),
    'bmp core' => "BM" . str_repeat("\0", 12) . pack('Vvvvv', 12, 7, 9, 1, 8),
    'psd' => "8BPS" . str_repeat("\0", 10) . pack('NN', 30, 40),
    'ico' => "\0\0\1\0" . pack('v', 2) . "\x10\x10\0\0\0\0\x08\0" . str_repeat("\0", 8) . "\x20\x40\0\0\0\0\x20\0" . str_repeat("\0", 8),
    'webp lossy' => "RIFF\0\0\0\0WEBPVP8 " . str_repeat("\0", 10) . pack('vv', 320, 200),
    'webp lossless' => "RIFF\0\0\0\0WEBPVP8L\0\0\0\0\x2f\x13\xc0\x31\x00\0",
    'wbmp' => "\0\0\x4b\x32",
    'xbm' => "#define test_width 12\n#define test_height 34\nstatic char test_bits[] = {};\n",
    'tiff ii' => "II*\0" . pack('V', 8) . pack('v', 2) . pack('vvVV', 0x100, 3, 1, 77) . pack('vvVV', 0x101, 4, 1, 88) . "\0\0\0\0",
    'tiff mm' => "MM\0*" . pack('N', 8) . pack('n', 2) . pack('nnNn', 0x100, 3, 1, 55) . "\0\0" . pack('nnNN', 0x101, 4, 1, 66) . "\0\0\0\0",
    'iff' => "FORM" . pack('N', 30) . "ILBM" . "BMHD" . pack('N', 20) . pack('nn', 11, 22) . "\0\0\0\0\x05" . str_repeat("\0", 11),
    'jpeg' => "\xff\xd8\xff\xe0" . pack('n', 6) . "JFIF" . "\xff\xe1" . pack('n', 5) . "abc" . "\x00\x00" . "\xff\xc0" . pack('n', 11) . "\x08" . pack('nn', 48, 64) . "\x03" . str_repeat("\0", 3) . "\xff\xda",
    'svg' => '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" width="120" height="40cm"></svg>',
    'svg px' => '<svg width="12px" height="34"></svg>',
    'svg bad' => '<svg width="12.5" height="34"></svg>',
    'html' => '<html></html>',
    'short' => "ab",
    'swf' => "FWS\x08" . pack('V', 100) . "\x78\x00\x05\x5f\x00\x00\x0f\xa0\x00\x00",
];
foreach ($images as $name => $data) {
    echo "-- $name --\n";
    $info = 'x';
    var_dump(getimagesizefromstring($data, $info));
    var_dump($info);
}

$file = tempnam(sys_get_temp_dir(), 'img');
file_put_contents($file, $images['jpeg']);
var_dump(getimagesize($file, $info)[3], array_keys($info));
var_dump(getimagesize('no-such-image-file.png'));

for ($t = 0; $t <= 22; $t++) {
    echo $t, ' ', image_type_to_mime_type($t), ' ', var_export(image_type_to_extension($t), true), ' ', var_export(image_type_to_extension($t, false), true), "\n";
}
var_dump(IMAGETYPE_JPEG2000, IMAGETYPE_COUNT, IMAGETYPE_SVG, IMAGETYPE_UNKNOWN);

// iptc
$iptc = "\x1c\x02\x05" . pack('n', 5) . "title" . "\x1c\x02\x19" . pack('n', 3) . "one" . "\x1c\x02\x19" . pack('n', 3) . "two";
var_dump(iptcparse($iptc), iptcparse("nothing"));
$embedded = iptcembed($iptc, $file);
var_dump(bin2hex($embedded));
file_put_contents($file, $embedded);
getimagesize($file, $info);
var_dump(iptcparse($info['APP13']));
ob_start();
var_dump(iptcembed("odd", $file, 2));
$printed = ob_get_clean();
var_dump(bin2hex($printed));
var_dump(@iptcembed("x", $file . '.missing'));
unlink($file);
