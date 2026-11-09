<?php
// fgetcsv, fputcsv, str_getcsv and SplFileObject's csv methods as php's
// php_fgetcsv / php_fputcsv do them
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) {
    echo "[$no] $msg\n";
    return true;
});

function show($v) {
    echo json_encode($v), "\n";
}

function attempt(callable $f) {
    try {
        show($f());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

echo "-- str_getcsv\n";
show(str_getcsv('a,b,c', escape: ''));
show(str_getcsv('', escape: ''));
show(str_getcsv("\r\n", escape: ''));
show(str_getcsv(',,,', escape: ''));
show(str_getcsv("0\t \t'2'\n", "\t", "'", ''));
show(str_getcsv('  "a" , "b"x ,c ', escape: ''));
show(str_getcsv('"a""b",c', escape: ''));
show(str_getcsv('"a\"b",c', escape: '\\'));
show(str_getcsv('"a\"b",c', escape: ''));
show(str_getcsv('"unterminated,field', escape: ''));
show(str_getcsv("\"multi\nline\",x", escape: ''));
show(str_getcsv("a,b\r\n", escape: ''));
show(str_getcsv("a\r,b\r", escape: ''));
show(str_getcsv('a;b;"c;d"', ';', escape: ''));
show(str_getcsv("'a''b'|c", '|', "'", ''));
var_export(str_getcsv("y", ",", "y", "\000"));
echo "\n";
var_export(str_getcsv("\0yy", "y", "y", "\0"));
echo "\n";
show(str_getcsv('a,b'));
show(str_getcsv(123, escape: ''));
show(str_getcsv('1.5', '.', escape: ''));

echo "-- argument errors\n";
attempt(fn() => str_getcsv('a', '', escape: ''));
attempt(fn() => str_getcsv('a', ',,', escape: ''));
attempt(fn() => str_getcsv('a', ',', '', ''));
attempt(fn() => str_getcsv('a', ',', '"', 'ab'));
attempt(fn() => str_getcsv([]));
attempt(fn() => str_getcsv('a', []));
attempt(fn() => str_getcsv('a', null, escape: ''));
attempt(fn() => fgetcsv(false));
attempt(fn() => fgetcsv(null));
attempt(fn() => fputcsv(STDOUT, 'x'));
$fp = fopen('php://memory', 'w+');
attempt(fn() => fgetcsv($fp, -1, escape: ''));
attempt(fn() => fgetcsv($fp, 1, ',,', escape: ''));
attempt(fn() => fgetcsv($fp, 1, ',', '', ''));
attempt(fn() => fgetcsv($fp, 1, ',', '"', 'xx'));
attempt(fn() => fgetcsv($fp, 'abc', escape: ''));
attempt(fn() => fputcsv($fp, [], '', escape: ''));
attempt(fn() => fputcsv($fp, [], ',', 'xx', ''));
attempt(fn() => fputcsv($fp, [], ',', '"', 'xx'));
attempt(fn() => fputcsv($fp, [], ',,', []));
fclose($fp);
attempt(fn() => fgetcsv($fp));

echo "-- fgetcsv\n";
$fp = fopen('php://memory', 'w+');
fwrite($fp, "a,b,c\n\n\"multi\nline\",x\n  \"sp\" ,y\r\nlast,\"open\nrest\nmore");
rewind($fp);
while (($row = fgetcsv($fp, escape: '')) !== false) {
    show($row);
}
var_dump(feof($fp));
rewind($fp);
show(fgetcsv($fp, 3, escape: ''));
show(fgetcsv($fp, 3, escape: ''));
show(fgetcsv($fp, 0, escape: ''));
show(fgetcsv($fp, null, escape: ''));
rewind($fp);
show(fgetcsv($fp, escape: '', length: 2));
fclose($fp);

echo "-- fputcsv\n";
$fp = fopen('php://memory', 'w+');
var_dump(fputcsv($fp, ['a', 'b c', 'd"e', "f\ng", 'h,i', 'j\\"k', '', null, 1.5, true, false, 7], escape: ''));
var_dump(fputcsv($fp, ['a\\"b', 'x\\', 'q"'], escape: '\\'));
var_dump(fputcsv($fp, ['tab	x', "cr\rx", 'plain'], ';', "'", '', "\r\n"));
var_dump(fputcsv($fp, [], escape: ''));
var_dump(fputcsv($fp, ['k' => 'v', 5 => 'w'], escape: '', eol: null));
var_dump(fputcsv($fp, [[1]], escape: ''));
var_dump(fputcsv($fp, ['x']));
rewind($fp);
echo stream_get_contents($fp);
fclose($fp);
$ro = fopen('php://memory', 'r');
var_dump(fputcsv($ro, ['a'], escape: ''));

echo "-- round trip\n";
$fp = fopen('php://memory', 'w+');
$rows = [['id', 'note'], [1, "say \"hi\"\nthere"], [2, ' padded '], [3, 'x\\y']];
foreach ($rows as $r) fputcsv($fp, $r, escape: '');
rewind($fp);
while (($row = fgetcsv($fp, escape: '')) !== false) show($row);
fclose($fp);

echo "-- utf-8 locale\n";
show(str_getcsv("\xC3\xA9\xA9b", "\xA9", escape: ''));
if (setlocale(LC_ALL, 'C.UTF-8', 'C.utf8', 'en_US.UTF-8') !== false) {
    show(str_getcsv("\xC3\xA9\xA9b", "\xA9", escape: ''));
    show(str_getcsv("\"first #\xD1\x81\xD8\x80\";\"second\"", ';', '"', '#'));
    setlocale(LC_ALL, 'C');
}

echo "-- SplFileObject\n";
$name = tempnam(sys_get_temp_dir(), 'csv');
file_put_contents($name, "a,b\n\n'x;y'|z\n\r\nlast\n");
$file = new SplFileObject($name);
show($file->getCsvControl());
attempt(fn() => $file->fgetcsv());
$file->setCsvControl(escape: '');
show($file->fgetcsv());
show($file->fgetcsv());
show($file->fgetcsv("|", "'"));
attempt(fn() => $file->fgetcsv('ab'));
attempt(fn() => $file->fgetcsv(',', ''));
attempt(fn() => $file->fgetcsv(',', '"', 'ab'));
attempt(fn() => $file->setCsvControl(''));
attempt(fn() => $file->setCsvControl(',', 'xy'));
attempt(fn() => $file->setCsvControl(',', '"', 'xy'));
$file->setCsvControl(';', "'", '');
show($file->getCsvControl());
$file->setCsvControl();
show($file->getCsvControl());
$file->setCsvControl('|', "'", '');

foreach ([0, SplFileObject::SKIP_EMPTY, SplFileObject::SKIP_EMPTY | SplFileObject::DROP_NEW_LINE, SplFileObject::SKIP_EMPTY | SplFileObject::DROP_NEW_LINE | SplFileObject::READ_AHEAD] as $extra) {
    $file->setFlags(SplFileObject::READ_CSV | $extra);
    echo "flags ", $file->getFlags(), "\n";
    foreach ($file as $row) show($row);
}

$out = new SplFileObject($name, 'w+');
attempt(fn() => $out->fputcsv(['a b', 'c']));
$out->setCsvControl(escape: '');
var_dump($out->fputcsv(['a b', 'c']));
var_dump($out->fputcsv(['d', 'e;f'], ';', "'", '', "\r\n"));
attempt(fn() => $out->fputcsv(['x'], ''));
attempt(fn() => $out->fputcsv('x'));
$out->rewind();
echo $out->fread(100);
$out = null;
$file = null;
unlink($name);

$tmp = new SplTempFileObject();
$tmp->setCsvControl(escape: '');
$tmp->fputcsv(['1', 'two words']);
$tmp->fputcsv(['3', "multi\nline"]);
$tmp->rewind();
$tmp->setFlags(SplFileObject::READ_CSV | SplFileObject::SKIP_EMPTY | SplFileObject::READ_AHEAD);
foreach ($tmp as $row) show($row);

echo "-- SplFileObject keys and seek\n";
$name = tempnam(sys_get_temp_dir(), 'csv');
file_put_contents($name, "a,1\n\nb,2\n\"c\nd\",3\nlast,4");
$file = new SplFileObject($name);
$file->setCsvControl(escape: '');
foreach ([SplFileObject::READ_CSV, SplFileObject::READ_CSV | SplFileObject::SKIP_EMPTY | SplFileObject::DROP_NEW_LINE, SplFileObject::SKIP_EMPTY | SplFileObject::DROP_NEW_LINE, SplFileObject::READ_AHEAD | SplFileObject::DROP_NEW_LINE] as $flags) {
    $file->setFlags($flags);
    foreach ($file as $k => $row) echo $k, ' ', json_encode($row), "\n";
    foreach ([0, 1, 3, 9] as $line) {
        $file->seek($line);
        echo "seek $line: ", $file->key(), ' ', json_encode($file->current()), "\n";
    }
}
$file->setFlags(0);
$file->rewind();
show($file->fgetcsv());
echo $file->key(), ' ', json_encode($file->current()), "\n";
show($file->fgetcsv());
echo $file->key(), ' ', json_encode($file->current()), "\n";
$file->setFlags(SplFileObject::READ_CSV);
show($file->fgetcsv());
echo $file->key(), ' ', json_encode($file->current()), "\n";
$file = null;
unlink($name);
