<?php
// string functions ported from php: argument checks, warnings, edge cases
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
function t(callable $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

// trim family: default set, ranges, malformed ranges, single characters
t(fn() => rtrim("rtrim test        ", "\x00..\x1F"));
t(fn() => ltrim("        ltrim test", "\x00..\x1F"));
t(fn() => trim("\t testing trim  ", "\t"));
t(fn() => trim("  Hello World  ", "..a"));
t(fn() => trim("  Hello World  ", "a.."));
t(fn() => trim("  Hello World  ", "z..a"));
t(fn() => trim("  Hello World  ", "a..b..c"));
t(fn() => chop("abc\0\n"));
t(fn() => trim([]));
t(fn() => trim(123, 1));

// addcslashes and the slash strippers
t(fn() => addcslashes("zoo['.']", 'z..A'));
t(fn() => addcslashes("abc\0\x01\x7f\xff\n", "\0..\37!@\177..\377"));
t(fn() => addcslashes("", "a"));
t(fn() => addcslashes("abc", ""));
t(fn() => stripslashes('hello\0world\\'));
t(fn() => stripcslashes('\x41\101\n\q\x4g'));

// strtok keeps its string between calls and forgets it at the end
t(fn() => strtok("a b  c", " "));
t(fn() => strtok(" "));
t(fn() => strtok(" "));
t(fn() => strtok(" "));
t(fn() => strtok(" "));
t(fn() => strtok("x", null));

// strtr in both forms
t(fn() => strtr("abc", "ab", "123"));
t(fn() => strtr("abc", ["" => "x"]));
t(fn() => strtr("abc", ["" => "x", "a" => "1"]));
t(fn() => strtr("012atm", [0 => "a", 1 => "b", "atm" => "ATM"]));
t(fn() => strtr("hi all, I said hello", ["hi" => "hello", "hello" => "hi", "said" => "x"]));
t(fn() => strtr("abc", 1));
t(fn() => strtr("", []));
t(fn() => strtr("1111", [1 => 2]));

// str_replace and str_ireplace
t(fn() => str_replace("a", ["x"], "abc"));
t(fn() => str_replace(["a", "b", ""], ["1"], "abcab", $c));
var_dump($c ?? null);
t(fn() => str_ireplace(["A", "BC"], ["x", "y"], ["abc", "ABC" => "aBc", 5 => 12]));
t(fn() => str_replace([[1]], "x", "Array"));
t(fn() => str_replace(fopen("php://memory", "r"), "x", "y"));
t(fn() => str_replace("a", "b", null));
$s = "aaa";
t(fn() => str_replace("a", "aa", $s, $count));
var_dump($count);

// implode and join
t(fn() => implode(", ", [1, 2.5, true, null, "x"]));
t(fn() => implode([1, 2]));
t(fn() => join("-", [[1], 2]));
t(fn() => implode(", "));
t(fn() => join(", "));
t(fn() => implode([1], [2]));
t(fn() => implode(", ", 5));
t(fn() => implode(["a"], ", "));

// natural and length-bounded comparisons
t(fn() => strnatcmp("img12", "img10"));
t(fn() => strnatcasecmp("A1", "a01"));
t(fn() => strnatcmp(" 5", "5"));
t(fn() => strncmp("abc\0d", "abc\0e", 10));
t(fn() => strncmp("abcde", "abc", 10));
t(fn() => strncasecmp("ABC", "abd", -1));

// counting and comparing pieces
t(fn() => substr_count("hello hello", "ll", -5));
t(fn() => substr_count("hello", "l", 1, -1));
t(fn() => substr_count("hello", ""));
t(fn() => substr_count("hello", "l", 10));
t(fn() => substr_count("hello", "l", 0, 10));
t(fn() => substr_compare("abcde", "bc", 1, 2));
t(fn() => substr_compare("abcde", "BC", 1, 2, true));
t(fn() => substr_compare("abcde", "bc", 1, -1));
t(fn() => substr_compare("abcde", "bc", 10));
t(fn() => substr_compare("abcde", "de", -10));

// searching
t(fn() => strpbrk("This is a test", "st"));
t(fn() => strpbrk("This is a test", ""));
t(fn() => strrchr("a\0b\0c", ""));
t(fn() => strrchr("hello", "l", true));
t(fn() => strstr("user@example.com", "@", true));
t(fn() => stristr("HayStack", "st"));
t(fn() => stristr("HayStack", []));
t(fn() => strpos("abc", "c", -1));
t(fn() => stripos("abc", "C", 4));
t(fn() => strrpos("hello", "l", -2));
t(fn() => strrpos("hello", "l", -10));
t(fn() => strrpos("hello", "l", 1.5));
t(fn() => strripos("HELLO", "l", -3));
t(fn() => strripos("HELLO", "LL", -2));
t(fn() => strripos("hello world", "O", 5));
t(fn() => strrpos("", "", 0));

// ucwords and chunk_split
t(fn() => ucwords("hello_world-foo bar", "_-"));
t(fn() => ucwords("testing\x0cucwords"));
t(fn() => chunk_split("abcdefg", 3, "|"));
t(fn() => chunk_split("abc", 10, "|"));
t(fn() => chunk_split("abc", 0));
t(fn() => chunk_split("abc", PHP_INT_MAX + 1));
