<?php
// the standard filters: string.*, convert.*, dechunk, consumed, zlib.*, and
// php://filter

function through(string $filter, string $data, $params = null, int $chain = STREAM_FILTER_READ): string {
    if ($chain === STREAM_FILTER_WRITE) {
        $file = tempnam(sys_get_temp_dir(), 'zw');
        $fp = fopen($file, 'w');
        $params === null ? stream_filter_append($fp, $filter, $chain) : stream_filter_append($fp, $filter, $chain, $params);
        fwrite($fp, $data);
        fclose($fp);
        $out = file_get_contents($file);
        unlink($file);
        return $out;
    }
    $fp = fopen('php://temp', 'w+');
    fwrite($fp, $data);
    rewind($fp);
    $params === null ? stream_filter_append($fp, $filter, $chain) : stream_filter_append($fp, $filter, $chain, $params);
    $out = stream_get_contents($fp);
    fclose($fp);
    return $out;
}

$text = "Hello World! The quick brown fox.";
var_dump(through('string.rot13', $text));
var_dump(through('string.toupper', $text));
var_dump(through('string.tolower', $text));
var_dump(through('STRING.TOUPPER', $text));

var_dump($b64 = through('convert.base64-encode', $text));
var_dump(through('convert.base64-decode', $b64));
var_dump(through('convert.base64-encode', str_repeat('x', 100), ['line-length' => 20, 'line-break-chars' => "\n"]));
var_dump(through('convert.base64-encode', str_repeat('y', 30), ['line-length' => 8]));
var_dump(through('convert.quoted-printable-encode', "caf\xc3\xa9 = tea \t\nnext"));
var_dump(through('convert.quoted-printable-encode', str_repeat("long line ", 12), ['line-length' => 30, 'line-break-chars' => "\r\n"]));
var_dump(through('convert.quoted-printable-encode', "a b", ['binary' => true]));
var_dump(through('convert.quoted-printable-decode', "caf=C3=A9 =3D tea=\r\nsoft break"));

// a bad sequence makes the filter fail
$fp = fopen('php://temp', 'w+');
fwrite($fp, "abc=zz");
rewind($fp);
stream_filter_append($fp, 'convert.quoted-printable-decode');
var_dump(fread($fp, 100));

var_dump(through('dechunk', "5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"));
var_dump(through('dechunk', "a;ext=1\r\n0123456789\r\n0\r\n"));

// zlib
$deflated = through('zlib.deflate', str_repeat('compress me ', 20), ['level' => 9], STREAM_FILTER_WRITE);
var_dump(strlen($deflated) < 240, gzinflate($deflated) === str_repeat('compress me ', 20));
var_dump(through('zlib.inflate', gzdeflate('round trip')));
var_dump(through('zlib.inflate', gzencode('gzip data'), ['window' => 31]));

// php://filter with read= and write= chains
$file = tempnam(sys_get_temp_dir(), 'zf');
file_put_contents($file, "Some Text");
var_dump(file_get_contents("php://filter/read=string.toupper|string.rot13/resource=$file"));
var_dump(file_get_contents("php://filter/string.tolower/resource=$file"));
file_put_contents("php://filter/write=convert.base64-encode/resource=$file", "written");
var_dump(file_get_contents($file));
$fp = fopen("php://filter/read=convert.base64-decode/resource=$file", 'r');
var_dump(fread($fp, 100));
$meta = stream_get_meta_data($fp);
var_dump($meta['wrapper_type'], $meta['stream_type'], $meta['uri'] === "php://filter/read=convert.base64-decode/resource=$file");
fclose($fp);
var_dump(@file_get_contents("php://filter/read=no.such/resource=$file"));
var_dump(@file(" php://filter/resource=$file") === false);
unlink($file);

// consumed rewinds to what the next filter took
$fp = fopen('php://temp', 'w+');
fwrite($fp, "0123456789");
rewind($fp);
stream_filter_append($fp, 'consumed');
var_dump(fread($fp, 4));

foreach (['zlib.*', 'string.rot13', 'string.toupper', 'string.tolower', 'convert.*', 'consumed', 'dechunk'] as $name) {
    var_dump(in_array($name, stream_get_filters()));
}
echo "done\n";
