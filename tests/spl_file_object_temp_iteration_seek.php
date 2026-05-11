<?php
error_reporting(0);
$tmp = tempnam(sys_get_temp_dir(), "sfo_");
file_put_contents($tmp, "line1\nline2\nline3");

$f = new SplFileObject($tmp);
echo $f->fgets();
echo $f->fgets();
echo $f->fgets();
echo $f->eof() ? "y" : "n", "\n";

$f = new SplFileObject($tmp);
foreach ($f as $line) echo trim($line), " ";
echo "\n";

$f = new SplFileObject($tmp);
$f->seek(1);
echo trim($f->current()), "\n";
echo $f->key(), "\n";

$f = new SplFileObject($tmp);
$f->setFlags(SplFileObject::DROP_NEW_LINE);
foreach ($f as $line) echo "[", $line, "] ";
echo "\n";

$f = new SplFileObject($tmp);
$f->setFlags(SplFileObject::READ_AHEAD | SplFileObject::DROP_NEW_LINE);
foreach ($f as $k => $line) echo "$k=$line ";
echo "\n";

$csv = tempnam(sys_get_temp_dir(), "csv_");
file_put_contents($csv, "a,b,c\n1,2,3");
$f = new SplFileObject($csv);
print_r($f->fgetcsv());
print_r($f->fgetcsv());

$tsv = tempnam(sys_get_temp_dir(), "tsv_");
file_put_contents($tsv, "a\tb\tc\n1\t2\t3");
$f = new SplFileObject($tsv);
$f->setCsvControl("\t");
print_r($f->fgetcsv());
print_r($f->fgetcsv());

$out = tempnam(sys_get_temp_dir(), "out_");
$f = new SplFileObject($out, "w");
$f->fputcsv(["a", "b", "c"]);
$f->fputcsv(["1", "2", "3"]);
$f = null;
echo file_get_contents($out);

unlink($tmp);
unlink($csv);
unlink($tsv);
unlink($out);

$temp = new SplTempFileObject;
$temp->fwrite("temp data\nline 2");
$temp->rewind();
echo $temp->fgets();
echo $temp->fgets();
