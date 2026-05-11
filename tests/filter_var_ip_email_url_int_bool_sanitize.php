<?php
echo filter_var("alice@example.com", FILTER_VALIDATE_EMAIL), "\n";
echo filter_var("alice+tag@example.co.uk", FILTER_VALIDATE_EMAIL), "\n";
echo filter_var("invalid", FILTER_VALIDATE_EMAIL) === false ? "f" : "y", "\n";
echo filter_var("alice@", FILTER_VALIDATE_EMAIL) === false ? "f" : "y", "\n";
echo filter_var("@example.com", FILTER_VALIDATE_EMAIL) === false ? "f" : "y", "\n";
echo filter_var("", FILTER_VALIDATE_EMAIL) === false ? "f" : "y", "\n";

echo filter_var("https://example.com", FILTER_VALIDATE_URL), "\n";
echo filter_var("http://example.com/path?q=1", FILTER_VALIDATE_URL), "\n";
echo filter_var("ftp://user@host/path", FILTER_VALIDATE_URL), "\n";
echo filter_var("not a url", FILTER_VALIDATE_URL) === false ? "f" : "y", "\n";
echo filter_var("just text", FILTER_VALIDATE_URL) === false ? "f" : "y", "\n";

echo filter_var("192.168.1.1", FILTER_VALIDATE_IP), "\n";
echo filter_var("10.0.0.0", FILTER_VALIDATE_IP), "\n";
echo filter_var("255.255.255.255", FILTER_VALIDATE_IP), "\n";
echo filter_var("256.0.0.1", FILTER_VALIDATE_IP) === false ? "f" : "y", "\n";
echo filter_var("not.ip.addr", FILTER_VALIDATE_IP) === false ? "f" : "y", "\n";

echo filter_var("::1", FILTER_VALIDATE_IP), "\n";
echo filter_var("2001:db8::1", FILTER_VALIDATE_IP), "\n";

echo filter_var("192.168.1.1", FILTER_VALIDATE_IP, FILTER_FLAG_IPV4), "\n";
echo filter_var("::1", FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) === false ? "f" : "y", "\n";
echo filter_var("::1", FILTER_VALIDATE_IP, FILTER_FLAG_IPV6), "\n";
echo filter_var("192.168.1.1", FILTER_VALIDATE_IP, FILTER_FLAG_IPV6) === false ? "f" : "y", "\n";

echo filter_var("10.0.0.1", FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE) === false ? "f" : "y", "\n";
echo filter_var("8.8.8.8", FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE), "\n";

echo filter_var("42", FILTER_VALIDATE_INT), "\n";
echo filter_var("-42", FILTER_VALIDATE_INT), "\n";
echo filter_var("0", FILTER_VALIDATE_INT), "\n";
echo filter_var("42.5", FILTER_VALIDATE_INT) === false ? "f" : "y", "\n";
echo filter_var("abc", FILTER_VALIDATE_INT) === false ? "f" : "y", "\n";
echo filter_var("0x1A", FILTER_VALIDATE_INT) === false ? "f" : "y", "\n";

echo var_export(filter_var("42", FILTER_VALIDATE_INT), true), "\n";

$opts = ["options" => ["min_range" => 1, "max_range" => 100]];
echo filter_var("50", FILTER_VALIDATE_INT, $opts), "\n";
echo filter_var("200", FILTER_VALIDATE_INT, $opts) === false ? "f" : "y", "\n";
echo filter_var("0", FILTER_VALIDATE_INT, $opts) === false ? "f" : "y", "\n";
echo filter_var("1", FILTER_VALIDATE_INT, $opts), "\n";
echo filter_var("100", FILTER_VALIDATE_INT, $opts), "\n";

echo filter_var("3.14", FILTER_VALIDATE_FLOAT), "\n";
echo filter_var("-3.14", FILTER_VALIDATE_FLOAT), "\n";
echo filter_var("0", FILTER_VALIDATE_FLOAT), "\n";
echo filter_var("42", FILTER_VALIDATE_FLOAT), "\n";
echo filter_var("abc", FILTER_VALIDATE_FLOAT) === false ? "f" : "y", "\n";

echo filter_var("true", FILTER_VALIDATE_BOOLEAN), "\n";
echo filter_var("yes", FILTER_VALIDATE_BOOLEAN), "\n";
echo filter_var("1", FILTER_VALIDATE_BOOLEAN), "\n";
echo filter_var("on", FILTER_VALIDATE_BOOLEAN), "\n";
echo filter_var("false", FILTER_VALIDATE_BOOLEAN) === false ? "f" : "y", "\n";
echo var_export(filter_var("false", FILTER_VALIDATE_BOOLEAN), true), "\n";
echo var_export(filter_var("off", FILTER_VALIDATE_BOOLEAN), true), "\n";
echo var_export(filter_var("0", FILTER_VALIDATE_BOOLEAN), true), "\n";
echo var_export(filter_var("no", FILTER_VALIDATE_BOOLEAN), true), "\n";
echo var_export(filter_var("maybe", FILTER_VALIDATE_BOOLEAN), true), "\n";
echo var_export(filter_var("maybe", FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE), true), "\n";

echo filter_var("123", FILTER_SANITIZE_NUMBER_INT), "\n";
echo filter_var("123abc", FILTER_SANITIZE_NUMBER_INT), "\n";
echo filter_var("-12.5", FILTER_SANITIZE_NUMBER_INT), "\n";
echo filter_var("abc-12", FILTER_SANITIZE_NUMBER_INT), "\n";

echo filter_var("12.34", FILTER_SANITIZE_NUMBER_FLOAT, FILTER_FLAG_ALLOW_FRACTION), "\n";
echo filter_var("12.34", FILTER_SANITIZE_NUMBER_FLOAT), "\n";

echo filter_var("hello<script>alert(1)</script>", FILTER_SANITIZE_SPECIAL_CHARS), "\n";
echo filter_var("a&b<c>d", FILTER_SANITIZE_SPECIAL_CHARS), "\n";
echo filter_var("hello\"world'", FILTER_SANITIZE_SPECIAL_CHARS), "\n";

echo filter_var("hello world", FILTER_SANITIZE_FULL_SPECIAL_CHARS), "\n";
echo filter_var("a&b", FILTER_SANITIZE_FULL_SPECIAL_CHARS), "\n";

echo filter_var("test  string  with  spaces", FILTER_DEFAULT), "\n";

echo filter_var("text\twith\ttabs", FILTER_DEFAULT), "\n";

echo filter_var("123abc", FILTER_VALIDATE_INT) === false ? "f" : "y", "\n";

echo filter_var(" 42 ", FILTER_VALIDATE_INT), "\n";
echo filter_var("+42", FILTER_VALIDATE_INT), "\n";

echo filter_var("user@subdomain.example.com", FILTER_VALIDATE_EMAIL), "\n";
echo filter_var("a.b.c@example.com", FILTER_VALIDATE_EMAIL), "\n";

echo filter_var("https://user:pass@example.com:8080/path?q=1#frag", FILTER_VALIDATE_URL), "\n";

echo filter_var("0.0.0.0", FILTER_VALIDATE_IP), "\n";
echo filter_var("127.0.0.1", FILTER_VALIDATE_IP), "\n";

echo filter_var("1.2.3", FILTER_VALIDATE_IP) === false ? "f" : "y", "\n";
echo filter_var("1.2.3.4.5", FILTER_VALIDATE_IP) === false ? "f" : "y", "\n";

$arr = filter_var_array(
    ["age" => "30", "name" => "alice", "email" => "alice@example.com"],
    [
        "age" => FILTER_VALIDATE_INT,
        "name" => FILTER_DEFAULT,
        "email" => FILTER_VALIDATE_EMAIL,
    ]
);
print_r($arr);
