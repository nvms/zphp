<?php
// parse_ini_string basic
$ini = '
key1=hello
num=42
flag_true=true
flag_false=false
empty=
quoted="this is quoted"

[section1]
foo=bar

[section2]
val=99
';

print_r(parse_ini_string($ini));
print_r(parse_ini_string($ini, true));
print_r(parse_ini_string($ini, true, INI_SCANNER_TYPED));

// inline comments
$ini2 = "key=value ; comment\nnum=42 ; another\n";
print_r(parse_ini_string($ini2));

// list arrays
$ini3 = "items[]=a\nitems[]=b\nitems[name]=alice\n";
print_r(parse_ini_string($ini3));

// invalid (unclosed bracket) returns false
@$r = parse_ini_string("[unclosed");
var_dump($r);

// fputcsv: bool/null formatting
$fh = fopen('php://memory', 'w+');
fputcsv($fh, [1, 2.5, null, true, false], ',', '"', '\\');
rewind($fh);
echo stream_get_contents($fh);  // 1,2.5,,1,
fclose($fh);

// fputcsv custom enclosure
$fh2 = fopen('php://memory', 'w+');
fputcsv($fh2, ['a', 'b'], '|', "'", '\\');
fputcsv($fh2, ["a'b", "c|d"], '|', "'", '\\');
rewind($fh2);
echo stream_get_contents($fh2);
fclose($fh2);

// fputcsv: escape char triggers quoting
$fh3 = fopen('php://memory', 'w+');
fputcsv($fh3, ['a"b', 'c\\d'], ',', '"', '\\');
rewind($fh3);
echo stream_get_contents($fh3);  // "a""b","c\d"
fclose($fh3);

// fputcsv: special chars in fields
$fh4 = fopen('php://memory', 'w+');
fputcsv($fh4, ['has,comma', 'has"quote', 'normal'], ',', '"', '\\');
fputcsv($fh4, [' leading', 'trailing ', 'mid space'], ',', '"', '\\');
rewind($fh4);
echo stream_get_contents($fh4);
fclose($fh4);
