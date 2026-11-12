<?php
// argument checks of the dns and address functions, as dns.c and
// basic_functions.c make them
$calls = [
    fn() => dns_check_record("\0"),
    fn() => dns_check_record(""),
    fn() => dns_check_record("php.net", "BOGUS"),
    fn() => checkdnsrr("", "A"),
    fn() => dns_get_mx("\0", $hosts),
    fn() => dns_get_record("\0"),
    fn() => dns_get_record("php.net", 15263480),
    fn() => dns_get_record("php.net", 0, $a, $b, true),
    fn() => dns_get_record("php.net", 70000, $a, $b, true),
    fn() => getprotobyname("\0"),
    fn() => getservbyname("\0", "tcp"),
    fn() => getservbyname("http", "tcp\0"),
    fn() => getservbyport(80, "tcp\0"),
    fn() => inet_pton("\0"),
    fn() => ip2long("\0"),
    fn() => gethostbyname("\0"),
    fn() => gethostbynamel("\0"),
    fn() => gethostbyaddr("\0"),
    fn() => gethostbyaddr("invalid"),
    fn() => gethostbyaddr("300.1.2.3"),
    fn() => gethostbyname(str_repeat("a", 256)),
    fn() => gethostbynamel(str_repeat("a", 256)),
    fn() => fsockopen("invalid://127.0.0.1", 31337, $errno, $errstr),
    fn() => time_nanosleep(-1, 0),
    fn() => time_nanosleep(0, -1),
    fn() => time_nanosleep(0, 1000000000),
    fn() => time_sleep_until(-1),
    fn() => time_sleep_until(1),
    fn() => exec("a\0b"),
    fn() => system("a\0b"),
    fn() => passthru("a\0b"),
    fn() => exec(""),
];
foreach ($calls as $i => $call) {
    try {
        var_dump($call());
    } catch (Throwable $e) {
        echo $i, " ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}
foreach (["1.2.3.4", "255.255.255.255", "256.1.1.1", "1.2.3", "1.2.3.4.5", "01.2.3.4", "0.0.0.0", "1.2.3.04", " 1.2.3.4", "1.2.3.4 ", "0x1.2.3.4", "1..3.4", ""] as $ip) {
    var_dump(ip2long($ip));
}
var_dump(gethostbyaddr("127.0.0.1") !== false, socket_get_status(fopen("php://memory", "r"))["stream_type"]);
