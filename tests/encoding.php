<?php
echo base64_encode("Hello World");
echo "\n";
echo base64_decode("SGVsbG8gV29ybGQ=");
echo "\n";
echo base64_encode("");
echo "\n";
echo base64_decode(base64_encode("test 123!@#"));
echo "\n";

echo urlencode("hello world");
echo "\n";
echo urldecode("hello+world");
echo "\n";
echo rawurlencode("hello world");
echo "\n";
echo rawurldecode("hello%20world");
echo "\n";

echo md5("hello");
echo "\n";
echo sha1("hello");
echo "\n";

echo strrev("Hello");
echo "\n";

echo mb_substr("Hello", 1, 3);
echo "\n";
