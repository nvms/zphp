<?php
$path = sys_get_temp_dir() . "/_zphp_splfile_probe.txt";
file_put_contents($path, "hello world\nmore\n");

$info = new SplFileInfo($path);
echo $info->getPathname(), "\n";
echo $info->getFilename(), "\n";
echo $info->getBasename(), "\n";
echo $info->getBasename(".txt"), "\n";
echo $info->getExtension(), "\n";
echo $info->getPath(), "\n";

echo $info->isFile() ? "y" : "n", "\n";
echo $info->isDir() ? "y" : "n", "\n";
echo $info->isReadable() ? "y" : "n", "\n";
echo $info->isWritable() ? "y" : "n", "\n";
echo $info->isLink() ? "y" : "n", "\n";

echo strlen($info->getRealPath()) > 0 ? "y" : "n", "\n";
echo str_ends_with($info->getRealPath(), "_zphp_splfile_probe.txt") ? "y" : "n", "\n";

echo $info->getSize() > 0 ? "y" : "n", "\n";

$mt = $info->getMTime();
echo is_int($mt) && $mt > 0 ? "y" : "n", "\n";

$info2 = new SplFileInfo("$path");
echo (string)$info2, "\n";

$info3 = new SplFileInfo("/tmp/does/not/exist.txt");
echo $info3->getPathname(), "\n";
echo $info3->getFilename(), "\n";
echo $info3->getExtension(), "\n";
echo $info3->isFile() ? "y" : "n", "\n";
echo var_export($info3->getRealPath(), true), "\n";

$dir = new SplFileInfo("/tmp");
echo $dir->isDir() ? "y" : "n", "\n";
echo $dir->isFile() ? "y" : "n", "\n";
echo $dir->getBasename(), "\n";

$info = new SplFileInfo("/path/to/archive.tar.gz");
echo $info->getExtension(), "\n";
echo $info->getBasename(), "\n";
echo $info->getBasename(".gz"), "\n";
echo $info->getBasename(".tar.gz"), "\n";

$info = new SplFileInfo("just_filename.php");
echo $info->getFilename(), "\n";
echo $info->getExtension(), "\n";

$info = new SplFileInfo("/no/extension");
echo $info->getExtension(), "\n";
echo $info->getFilename(), "\n";

$info = new SplFileInfo("$path");
$f = $info->openFile();
echo get_class($f), "\n";

$content = "";
while (!$f->eof()) {
    $line = $f->fgets();
    if ($line === false) break;
    $content .= $line;
}
echo strlen($content) > 0 ? "y" : "n", "\n";

$f = new SplFileObject("$path", "r");
echo $f->fgets(), "";
echo $f->fgets(), "";

$f = new SplFileObject("$path", "r");
$f->setFlags(SplFileObject::DROP_NEW_LINE);
foreach ($f as $k => $line) {
    if (!$f->eof() || $line !== "") echo $k, ":", $line, "\n";
}

$f = new SplFileObject("$path", "r");
echo $f->ftell(), "\n";
$f->fseek(0);
echo $f->ftell(), "\n";
echo $f->fread(5), "\n";
echo $f->ftell(), "\n";

$f = new SplFileObject("$path", "r");
$f->setFlags(SplFileObject::READ_AHEAD | SplFileObject::DROP_NEW_LINE);
$f->seek(0);
echo $f->key(), ":", $f->current(), "\n";

$tmp = new SplTempFileObject;
$tmp->fwrite("a\nb\nc\n");
$tmp->rewind();
foreach ($tmp as $line) echo trim($line), " ";
echo "\n";

$info = new SplFileInfo("$path");
$obj = $info->openFile("r");
echo $obj instanceof SplFileObject ? "y" : "n", "\n";
echo $obj->getRealPath() === $info->getRealPath() ? "y" : "n", "\n";

$info = new SplFileInfo("$path");
echo $info->getType() === "file" ? "y" : "n", "\n";

