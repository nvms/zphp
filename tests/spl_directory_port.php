<?php
// SplFileInfo, DirectoryIterator and friends, SplFileObject: php's
// spl_directory behavior

$base = sys_get_temp_dir() . '/zphp_spl_dir_' . getmypid();
@mkdir($base);
@mkdir("$base/sub");
file_put_contents("$base/a.txt", "one\ntwo\n\nthree\n");
file_put_contents("$base/b.tar.gz", "x");
file_put_contents("$base/sub/c.csv", "x,y\n1,\"2\n3\"\n");
chdir($base);

echo "-- SplFileInfo\n";
foreach (['a/b/c.txt', '/tmp/', 'c.txt', '/', 'path/to/', 'd.'] as $p) {
    $i = new SplFileInfo($p);
    var_dump($i->getPathname(), $i->getPath(), $i->getFilename(), $i->getExtension(), $i->getBasename('.txt'));
    var_dump($i);
}
var_dump((string) new SplFileInfo('x/y'));
var_dump((new SplFileInfo('a/b/c'))->getPathInfo());
var_dump((new SplFileInfo('a.txt'))->getFileInfo());
var_dump((new SplFileInfo('a.txt'))->isFile(), (new SplFileInfo('sub'))->isDir(), (new SplFileInfo('a.txt'))->getSize());
foreach (['getMTime', 'getPerms', 'getInode', 'getOwner', 'getGroup', 'getSize', 'getType'] as $m) {
    try {
        (new SplFileInfo('missing'))->$m();
    } catch (RuntimeException $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
try {
    new SplFileInfo("bad\0name");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}

class MyInfo extends SplFileInfo {}
$i = new SplFileInfo('a.txt');
$i->setInfoClass('MyInfo');
var_dump(get_class($i->getFileInfo()), get_class($i->getPathInfo()));
try {
    $i->setInfoClass('stdClass');
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    $i->setFileClass('stdClass');
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
$f = $i->openFile();
var_dump(get_class($f), $f->fgets());

echo "-- DirectoryIterator\n";
$names = [];
foreach (new DirectoryIterator('.') as $k => $e) {
    $names[$e->getFilename()] = [$e->isDot(), $e->getExtension(), $e->getBasename('.gz')];
}
ksort($names);
var_dump($names);
$it = new DirectoryIterator('.');
$it->seek(2);
var_dump($it->key());
try {
    $it->seek(100);
} catch (OutOfBoundsException $e) {
    echo $e->getMessage(), "\n";
}
try {
    new DirectoryIterator('');
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    new DirectoryIterator('does_not_exist');
} catch (UnexpectedValueException $e) {
    echo $e->getMessage(), "\n";
}
try {
    $it->__construct('.');
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

echo "-- FilesystemIterator\n";
$fi = new FilesystemIterator('.');
printf("%08X\n", $fi->getFlags());
$fi->setFlags(FilesystemIterator::KEY_AS_FILENAME | FilesystemIterator::CURRENT_AS_PATHNAME);
printf("%08X\n", $fi->getFlags());
$out = iterator_to_array($fi);
ksort($out);
var_dump($out);
$fi = new FilesystemIterator('.', FilesystemIterator::KEY_AS_FILENAME);
$out = [];
foreach ($fi as $k => $v) $out[$k] = get_class($v);
ksort($out);
var_dump($out);
var_dump(FilesystemIterator::FOLLOW_SYMLINKS, FilesystemIterator::OTHER_MODE_MASK, FilesystemIterator::NEW_CURRENT_AND_KEY);

echo "-- RecursiveDirectoryIterator\n";
$rit = new RecursiveIteratorIterator(new RecursiveDirectoryIterator('.', FilesystemIterator::SKIP_DOTS | FilesystemIterator::UNIX_PATHS), RecursiveIteratorIterator::SELF_FIRST);
$out = [];
foreach ($rit as $path => $info) $out[$path] = [$rit->getSubPath(), $rit->getSubPathname()];
ksort($out);
var_dump($out);

echo "-- GlobIterator\n";
$g = new GlobIterator("$base/*.txt", FilesystemIterator::KEY_AS_FILENAME);
var_dump(count($g));
foreach ($g as $k => $v) var_dump($k, $v->getFilename());
var_dump(count(new GlobIterator("$base/*.none")));

echo "-- SplFileObject\n";
$f = new SplFileObject('a.txt');
foreach ($f as $n => $line) var_dump($n, $line);
$f->setFlags(SplFileObject::DROP_NEW_LINE | SplFileObject::SKIP_EMPTY | SplFileObject::READ_AHEAD);
foreach ($f as $n => $line) var_dump($n, $line);
$f->seek(1);
var_dump($f->key(), $f->current(), (string) $f);
var_dump($f->getFlags(), $f->getMaxLineLen());
$f->setMaxLineLen(2);
$f->rewind();
var_dump($f->fgets());
try {
    $f->setMaxLineLen(-1);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    $f->fread(0);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
$f = new SplFileObject('a.txt');
var_dump($f->fscanf('%s'));
$word = null;
var_dump($f->fscanf('%s', $word), $word);
var_dump(fclose(fopen('a.txt', 'r')));
try {
    new SplFileObject('sub');
} catch (LogicException $e) {
    echo $e->getMessage(), "\n";
}
try {
    new SplFileObject('missing.txt');
} catch (RuntimeException $e) {
    echo $e->getMessage(), "\n";
}
try {
    clone $f;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

$c = new SplFileObject('sub/c.csv');
$c->setFlags(SplFileObject::READ_CSV);
$c->setCsvControl(',', '"', '');
foreach ($c as $row) var_dump($row);
var_dump($c->getCsvControl());

echo "-- SplTempFileObject\n";
$t = new SplTempFileObject();
var_dump($t->getPathname(), $t->getFilename(), $t->getPath());
for ($i = 0; $i < 3; $i++) $t->fwrite("line $i\n");
$t->rewind();
while ($t->valid()) {
    echo $t->key(), ': ', $t->fgets();
}
var_dump($t->ftruncate(4), $t->fstat()['size']);
var_dump(new SplTempFileObject(-1));
var_dump((string) new SplTempFileObject());

unlink("$base/sub/c.csv");
rmdir("$base/sub");
unlink("$base/a.txt");
unlink("$base/b.tar.gz");
chdir('/');
rmdir($base);
