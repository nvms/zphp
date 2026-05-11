<?php
// covers: SoapClient construction in non-WSDL mode, __setLocation,
//   SoapHeader/SoapVar/SoapParam shape, SoapFault as Exception,
//   exception hierarchy, constants

echo "=== SoapClient basics ===\n";
$c = new SoapClient(null, [
    'location' => 'http://example.test/svc',
    'uri'      => 'urn:example:service',
    'soap_version' => SOAP_1_1,
    'trace'    => 1,
]);
echo "instanceof SoapClient: " . ($c instanceof SoapClient ? "yes" : "no") . "\n";

// rotate location and verify previous value
$prev = $c->__setLocation('http://b.test/');
echo "old location: $prev\n";
$prev = $c->__setLocation('http://c.test/');
echo "after rotate: $prev\n";

echo "\n=== SoapHeader shape ===\n";
$h = new SoapHeader('urn:example', 'session', 'tok-123', true, 'http://schemas.xmlsoap.org/soap/actor/next');
echo "namespace: $h->namespace\n";
echo "name: $h->name\n";
echo "data: $h->data\n";
echo "mustUnderstand: " . ($h->mustUnderstand ? "true" : "false") . "\n";

echo "\n=== SoapVar variants ===\n";
$vars = [
    new SoapVar('plain', XSD_STRING),
    new SoapVar(42, XSD_INT),
    new SoapVar(3.14, XSD_DOUBLE),
    new SoapVar(true, XSD_BOOLEAN),
];
foreach ($vars as $i => $v) {
    echo sprintf("[$i] type=%d value=%s\n", $v->enc_type, var_export($v->enc_value, true));
}

echo "\n=== SoapFault as Exception ===\n";
$f = new SoapFault('Client', 'invalid request', null, ['reason' => 'missing field']);
echo "code: $f->faultcode\n";
echo "string: $f->faultstring\n";
echo "is Exception: " . ($f instanceof Exception ? "yes" : "no") . "\n";
echo "is Throwable: " . ($f instanceof Throwable ? "yes" : "no") . "\n";
echo "getMessage(): " . $f->getMessage() . "\n";

try {
    throw new SoapFault('Server', 'oops');
} catch (SoapFault $e) {
    echo "caught as SoapFault: " . $e->getMessage() . "\n";
}

try {
    throw new SoapFault('Server', 'oops 2');
} catch (Exception $e) {
    echo "caught as Exception: " . get_class($e) . " => " . $e->getMessage() . "\n";
}

echo "\n=== SOAP constants ===\n";
$constants = [
    'SOAP_1_1' => SOAP_1_1,
    'SOAP_1_2' => SOAP_1_2,
    'SOAP_RPC' => SOAP_RPC,
    'SOAP_DOCUMENT' => SOAP_DOCUMENT,
    'SOAP_ENCODED' => SOAP_ENCODED,
    'SOAP_LITERAL' => SOAP_LITERAL,
    'WSDL_CACHE_NONE' => WSDL_CACHE_NONE,
    'WSDL_CACHE_DISK' => WSDL_CACHE_DISK,
    'XSD_STRING' => XSD_STRING,
    'XSD_BOOLEAN' => XSD_BOOLEAN,
    'XSD_INT' => XSD_INT,
];
foreach ($constants as $name => $val) {
    echo sprintf("  %-22s = %s\n", $name, var_export($val, true));
}
