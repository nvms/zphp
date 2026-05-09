<?php
// mb_strwidth
echo mb_strwidth("hello"), "\n";       // 5
echo mb_strwidth("héllo"), "\n";       // 5
echo mb_strwidth("日本語"), "\n";      // 6
echo mb_strwidth("hi 日本"), "\n";     // 7
echo mb_strwidth(""), "\n";

// CJK ranges
echo mb_strwidth("中"), "\n";   // 2
echo mb_strwidth("한"), "\n";   // 2 (Hangul)
echo mb_strwidth("ア"), "\n";   // 2 (Katakana)
echo mb_strwidth("a中b"), "\n"; // 4

// mb_encode_numericentity
echo mb_encode_numericentity("é", [0x80, 0xff, 0, 0xff]), "\n";
echo mb_encode_numericentity("Hello é!", [0x80, 0xff, 0, 0xff]), "\n";
echo mb_encode_numericentity("日本", [0x100, 0xffff, 0, 0xffff]), "\n";

// hex form
echo mb_encode_numericentity("é", [0x80, 0xff, 0, 0xff], 'UTF-8', true), "\n";

// mb_decode_numericentity
echo mb_decode_numericentity("&#233;", [0, 0xff, 0, 0xff]), "\n";
echo mb_decode_numericentity("Hello &#233;!", [0, 0xff, 0, 0xff]), "\n";
echo mb_decode_numericentity("&#x65;", [0, 0xff, 0, 0xff]), "\n";

// non-matching entities pass through
echo mb_decode_numericentity("&amp;", [0, 0xff, 0, 0xff]), "\n";

// chars outside range stay as-is in encode
echo mb_encode_numericentity("abc", [0x80, 0xff, 0, 0xff]), "\n";
