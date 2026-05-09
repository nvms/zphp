<?php
// gettype on resource (file handle)
$fh = fopen('php://memory', 'r+');
echo gettype($fh), "\n";
fclose($fh);

// gettype basics
echo gettype(null), "\n";
echo gettype(true), "\n";
echo gettype(42), "\n";
echo gettype(3.14), "\n";
echo gettype("hi"), "\n";
echo gettype([]), "\n";
echo gettype(new stdClass), "\n";

// settype mutations
$v = "42"; settype($v, 'integer'); var_dump($v);
$v = 1; settype($v, 'string'); var_dump($v);
$v = "1.5"; settype($v, 'float'); var_dump($v);
$v = 0; settype($v, 'boolean'); var_dump($v);
$v = "anything"; settype($v, 'null'); var_dump($v);

// settype invalid throws
try {
    $v = "x";
    settype($v, 'invalid_type');
    echo "no throw\n";
} catch (\ValueError $e) {
    echo "caught: ", $e->getMessage(), "\n";
}

// fprintf
$fh = fopen('php://memory', 'w+');
$ret = fprintf($fh, "n=%d s=%s\n", 42, "abc");
echo "ret:$ret\n";
rewind($fh);
echo stream_get_contents($fh);
fclose($fh);

// sprintf %c (single-byte char from int)
echo sprintf("%c", 65), "\n";
echo sprintf("%c", 97), "\n";
echo sprintf("%c%c%c", 72, 73, 33), "\n";

// sprintf positional args
echo sprintf('%1$s %2$s %1$s', 'a', 'b'), "\n";
echo sprintf('%2$d-%1$d', 3, 5), "\n";
echo sprintf('%1$03d', 7), "\n";
echo sprintf('Hello %2$s, %1$s!', 'world', 'there'), "\n";
echo sprintf('[%1$10s]', 'hi'), "\n";
echo sprintf('[%1$-10s]', 'hi'), "\n";

// is_* family
var_dump(is_int(42), is_integer(42), is_long(42));
var_dump(is_float(1.5), is_double(1.5));
var_dump(is_string("x"), is_array([]), is_object(new stdClass));
var_dump(is_null(null), is_bool(true));
