<?php
// addslashes / stripslashes
echo addslashes("hello 'world' \"php\""), "\n";
echo stripslashes("hello \\'world\\' \\\"php\\\""), "\n";
echo addslashes("a\\b"), "\n";  // escapes backslash too
echo addslashes("nul\0byte"), "\n";   // null byte
$s = "It's \"quoted\" with \\backslash";
$enc = addslashes($s);
echo $enc, "\n";
echo stripslashes($enc) === $s ? "rt-ok\n" : "rt-fail\n";

// addcslashes
echo addcslashes("hello world", "lo"), "\n"; // escape l and o
echo addcslashes("foo bar", "a..z"), "\n"; // range
echo addcslashes("ABC123", "0..9"), "\n";

// stripcslashes
echo stripcslashes("\\thello\\nworld"), "\n";  // tab + newline
echo stripcslashes("\\x41"), "\n";  // hex escape -> A
echo stripcslashes("\\101"), "\n";  // octal -> A
echo stripcslashes("\\?"), "\n";  // unknown -> just '?'

// quotemeta
echo quotemeta("Hello World."), "\n";
echo quotemeta("a + b * c"), "\n";
echo quotemeta("[test] (foo)"), "\n";
echo quotemeta("ab.c?d^"), "\n";

// preg_split with DELIM_CAPTURE
print_r(preg_split('/(\d+)/', 'abc1def22ghi', -1, PREG_SPLIT_DELIM_CAPTURE));
print_r(preg_split('/(\d+)/', 'abc1def22ghi', -1, PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_NO_EMPTY));
print_r(preg_split('/(\W+)/', 'hello, world. foo', 3, PREG_SPLIT_DELIM_CAPTURE));

// preg_split limit
print_r(preg_split('/[,\s]+/', 'a, b, c, d, e', 3));
print_r(preg_split('/[,\s]+/', 'a, b, c', -1));
print_r(preg_split('/x/', 'abc'));  // no match - one element
print_r(preg_split('//', 'abc')); // empty pattern
print_r(preg_split('//', 'abc', -1, PREG_SPLIT_NO_EMPTY));

// preg_split with PREG_SPLIT_OFFSET_CAPTURE
print_r(preg_split('/(\W+)/', 'hello, world', -1, PREG_SPLIT_OFFSET_CAPTURE));

// preg_match_all PREG_SET_ORDER + named groups
preg_match_all('/(?<key>\w+)=(?<val>\d+)/', 'a=1 b=22 c=333', $m, PREG_SET_ORDER);
print_r($m);
preg_match_all('/(?<key>\w+)=(?<val>\d+)/', 'a=1 b=22 c=333', $m, PREG_PATTERN_ORDER);
print_r($m);

// htmlspecialchars ENT_HTML5
echo htmlspecialchars("'", ENT_QUOTES | ENT_HTML5), "\n"; // &apos; in HTML5
echo htmlspecialchars("'", ENT_QUOTES), "\n"; // &#039; default
echo htmlspecialchars('<a href="x">', ENT_QUOTES | ENT_HTML5), "\n";

// html_entity_decode with default flags
echo html_entity_decode("&amp; &lt; &gt; &quot; &#039; &apos;"), "\n";
echo html_entity_decode("&apos;", ENT_QUOTES | ENT_HTML5), "\n";
echo html_entity_decode("&copy; &eacute; &ouml;"), "\n";

// htmlspecialchars_decode all forms
echo htmlspecialchars_decode("&lt;tag&gt; &amp; &quot;q&quot; &#039;a&#039; &apos;b&apos;"), "\n";
echo htmlspecialchars_decode("&lt;a href=&quot;x&quot;&gt;", ENT_NOQUOTES), "\n";

// SplStack iteration
$s = new SplStack();
$s->push(1); $s->push(2); $s->push(3);
foreach ($s as $v) echo $v, " "; // LIFO: 3 2 1
echo "\n";

// SplQueue iteration
$q = new SplQueue();
$q->enqueue("a"); $q->enqueue("b"); $q->enqueue("c");
foreach ($q as $v) echo $v, " ";
echo "\n";

// ArrayObject offset operations with object key (not allowed - PHP throws for object keys)
$ao = new ArrayObject();
$ao[1] = "int-key";
$ao["str"] = "str-key";
echo $ao[1], " ", $ao["str"], "\n";

// str_replace with regex special chars in search (no regex - literal)
echo str_replace("$2", "BAR", '$1 $2 $3'), "\n";
echo str_replace(".*", "X", "a.*b"), "\n";
echo str_replace("\\d", "N", '\d \w \s'), "\n";

// preg_quote
echo preg_quote("a.b/c[d]"), "\n";
echo preg_quote("a/b/c", "/"), "\n";
