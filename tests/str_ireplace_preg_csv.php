<?php
// number_format multibyte sep
echo number_format(1234567.89, 2, '.', "\xC2\xA0"), "\n"; // non-breaking space
echo number_format(1234567.89, 2, '.', '··'), "\n"; // multibyte
echo number_format(1234567.89, 2, "・", '·'), "\n"; // multibyte both

// pack/unpack X (back up) and @ (absolute position)
$packed = pack("c4", 1, 2, 3, 4);
echo bin2hex($packed), "\n";
print_r(unpack("c4/X3/c", $packed)); // X3 backs up 3, then read another c
print_r(unpack("@2/c", $packed)); // skip to position 2

// pack with X
$packed = pack("ccXc", 1, 2, 99); // 1, 2, back-up 1 then write 99 over
echo bin2hex($packed), "\n";

// pack @ absolute
$packed = pack("c@5c", 1, 9); // 1 byte, fill with NULs to position 5, then byte
echo bin2hex($packed), "\n";

// rewind/fseek
$path = sys_get_temp_dir() . "/zphp_seek.txt";
file_put_contents($path, "0123456789");
$f = fopen($path, "r");
fseek($f, 5);
echo fread($f, 3), "\n"; // 567
fseek($f, -2, SEEK_END);
echo fread($f, 5), "\n"; // 89
fseek($f, 2, SEEK_CUR); // already at 10, +2 = 12 (past EOF)
echo ftell($f), "\n";
rewind($f);
echo ftell($f), "\n"; // 0
fclose($f);
unlink($path);

// fputcsv with custom escape
$path = sys_get_temp_dir() . "/zphp_csv.csv";
$f = fopen($path, "w");
fputcsv($f, ["a,b", 'has "quotes"', "ok"], escape: "");
fputcsv($f, ["nl\nhere", "tab\there", "x"], escape: "");
fputcsv($f, ['back-slash', 'normal'], escape: "");
fclose($f);
echo file_get_contents($path), "---\n";
$f = fopen($path, "r");
while (($row = fgetcsv($f, escape: "")) !== false) print_r($row);
fclose($f);
unlink($path);

// str_replace returns array when subject is array
$r = str_replace("a", "X", ["aaa", "bbb"]);
print_r($r);

// str_ireplace
$r = str_ireplace("HELLO", "HI", "hello world");
echo $r, "\n";
$r = str_ireplace(["A", "B"], ["X", "Y"], "AaBb");
echo $r, "\n";
$r = str_ireplace("X", "Y", ["aXa", "BBB"]);
print_r($r);

// preg_grep with PREG_GREP_INVERT preserves keys
$arr = [10 => "apple", 20 => "banana", 30 => "cherry"];
print_r(preg_grep('/^a/', $arr));
print_r(preg_grep('/^a/', $arr, PREG_GREP_INVERT));

// preg_replace returns null on error
$r = @preg_replace('/(unclosed/', 'X', 'test');
var_dump($r);
echo preg_last_error_msg(), "\n";
