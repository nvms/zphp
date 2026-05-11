<?php
// covers: SoapClient lifecycle in non-WSDL mode, SoapHeader / SoapVar / SoapParam
//   shapes, SoapFault exception hierarchy, SOAP/XSD/WSDL_CACHE constants,
//   __setLocation/__setSoapHeaders/__setCookie return values

echo "=== SoapClient non-WSDL setup ===\n";
$client = new SoapClient(null, [
    'location' => 'http://services.example.test/calc',
    'uri'      => 'urn:example:calc',
    'soap_version' => SOAP_1_1,
    'compression' => SOAP_COMPRESSION_ACCEPT | SOAP_COMPRESSION_GZIP,
    'trace' => 1,
]);
echo "instanceof: " . ($client instanceof SoapClient ? "yes" : "no") . "\n";
echo "rotate location:\n";
$prev = $client->__setLocation('http://b/');
echo "  step 1 prev: $prev\n";
$prev = $client->__setLocation('http://c/');
echo "  step 2 prev: $prev\n";

echo "\n=== headers in flight ===\n";
$auth = new SoapHeader('urn:example:auth', 'Authorization', 'Bearer tok-123', true);
$session = new SoapHeader('urn:example:session', 'SessionId', 'sess-456', false);
$result = $client->__setSoapHeaders([$auth, $session]);
echo "set headers: " . ($result ? "true" : "false") . "\n";

echo "\n=== cookies ===\n";
$client->__setCookie('CSRF', 'abc');
$client->__setCookie('locale', 'en_US');
$cookies = $client->__getCookies();
$names = array_keys($cookies);
sort($names);
echo "cookie keys: " . implode(',', $names) . "\n";
echo "has CSRF: " . (isset($cookies['CSRF']) ? "yes" : "no") . "\n";
echo "has locale: " . (isset($cookies['locale']) ? "yes" : "no") . "\n";
echo "CSRF stored as: " . gettype($cookies['CSRF']) . "\n";
echo "CSRF value: " . $cookies['CSRF'][0] . "\n";

echo "\n=== SoapVar variety ===\n";
$vars = [
    'string' => new SoapVar('text', XSD_STRING),
    'int'    => new SoapVar(99, XSD_INT),
    'bool'   => new SoapVar(true, XSD_BOOLEAN),
    'double' => new SoapVar(1.5, XSD_DOUBLE),
    'long'   => new SoapVar(1234567890123, XSD_LONG),
];
foreach ($vars as $k => $v) {
    echo sprintf("  %-7s type=%d value=%s\n", $k, $v->enc_type, var_export($v->enc_value, true));
}

echo "\n=== SoapParam with named binding ===\n";
$param = new SoapParam(42, 'count');
echo "name: $param->param_name\n";
echo "data: $param->param_data\n";

echo "\n=== SoapFault hierarchy + catching ===\n";
function maybe_fault(bool $fail): void {
    if ($fail) throw new SoapFault('Server', 'service unavailable', null, ['retry_after' => 30]);
}

try { maybe_fault(true); } catch (SoapFault $e) {
    echo "caught: " . $e->faultcode . " / " . $e->faultstring . "\n";
    echo "detail.retry_after: " . $e->detail['retry_after'] . "\n";
}
try { maybe_fault(true); } catch (Exception $e) {
    echo "caught as Exception: " . get_class($e) . "\n";
}
try { maybe_fault(false); } catch (SoapFault $e) {
    echo "leaked\n";
}
echo "no-fault path completed\n";

echo "\n=== SOAP constants table ===\n";
$consts = [
    'SOAP_1_1', 'SOAP_1_2', 'SOAP_RPC', 'SOAP_DOCUMENT', 'SOAP_ENCODED', 'SOAP_LITERAL',
    'WSDL_CACHE_NONE', 'WSDL_CACHE_MEMORY', 'WSDL_CACHE_DISK', 'WSDL_CACHE_BOTH',
    'XSD_STRING', 'XSD_BOOLEAN', 'XSD_INT', 'XSD_LONG', 'XSD_DOUBLE',
];
foreach ($consts as $c) {
    echo sprintf("  %-22s = %d\n", $c, constant($c));
}
