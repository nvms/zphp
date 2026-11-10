<?php
// more string functions ported from php: padding, wrapping, replacing
// pieces, byte helpers, explode, soundex, word counts and uuencoding
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
function t(callable $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

t(fn() => str_pad("5", 3, "0", STR_PAD_LEFT));
t(fn() => str_pad("abc", 10, "-=", STR_PAD_BOTH));
t(fn() => str_pad("abc", 2));
t(fn() => str_pad("abc", 10, ""));
t(fn() => str_pad("abc", 10, " ", 5));
t(fn() => str_pad("abc", PHP_INT_MAX + 1));

foreach (["a", "Az", "zz", "Zz", "9", "a9", "Zz9"] as $s) t(fn() => str_increment($s));
foreach (["b", "Ba", "aa", "10", "a0", "A", "0", "1"] as $s) t(fn() => str_decrement($s));
t(fn() => str_increment(""));
t(fn() => str_decrement("a-b"));

t(fn() => nl2br("a\r\nb\n\rc\rd\ne"));
t(fn() => nl2br("x\n", false));

t(fn() => wordwrap("The quick brown fox sat over the lazy dog", 15, "<br />\n"));
t(fn() => wordwrap("A very long woooooooooooord.", 8, "\n", true));
t(fn() => wordwrap("abc abc", 3, "\n"));
t(fn() => wordwrap("ab-cd", 2, "-", true));
t(fn() => wordwrap("testing", 0, "\n", true));
t(fn() => wordwrap("testing", 5, ""));

t(fn() => substr_replace("Hello", "J", 0, 1));
t(fn() => substr_replace("Hello", ["J", "x"], -2));
t(fn() => substr_replace("Hello", "J", [0]));
t(fn() => substr_replace("Hello", "J", 0, [1]));
t(fn() => substr_replace(["abc" => "xxxkk", "def" => "xxxdd", 4 => "hello"], "zzz", [0, 1], [3]));
t(fn() => substr_replace(["one", "two"], ["1"], 1, 0));

t(fn() => ord(""));
t(fn() => ord("Hello"));
t(fn() => chr(321));
t(fn() => chr(-1));
t(fn() => chr(10.5));

t(fn() => count_chars("abacus", 1));
t(fn() => count_chars("abacus", 3));
t(fn() => strlen(count_chars("abacus", 4)));
t(fn() => count_chars("abc", 5));

t(fn() => explode(",", "a,b,,c", 2));
t(fn() => explode(",", "a,b,,c", -2));
t(fn() => explode(",", "a,b,,c", 0));
t(fn() => explode(",", "", -1));
t(fn() => explode(",", ""));
t(fn() => explode("", "abc"));
t(fn() => explode(0, "1020"));

foreach (["", "Euler", "Tymczak", "Pfister", "Ashcraft", "lloyd", "12"] as $s) t(fn() => soundex($s));

t(fn() => str_word_count("Hello fri3nd, you're looking good today!"));
t(fn() => str_word_count("Hello fri3nd, you're looking good today!", 1, "0..9"));
t(fn() => str_word_count("-foo- 'bar' baz-", 2));
t(fn() => str_word_count("x", 3));

t(fn() => convert_uuencode(""));
t(fn() => convert_uuencode("test\ntext text text\r\n"));
t(fn() => convert_uudecode(convert_uuencode(str_repeat("abc", 30))));
t(fn() => convert_uudecode("x"));
t(fn() => convert_uudecode(""));
