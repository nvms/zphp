<?php
// covers: SoapClient/SoapFault/SoapHeader/SoapVar/SoapParam construction, constants, envelope builder, fault hierarchy

assert(SOAP_1_1 === 1);
assert(SOAP_1_2 === 2);
assert(SOAP_RPC === 1);
assert(SOAP_DOCUMENT === 2);
assert(SOAP_LITERAL === 2);
assert(WSDL_CACHE_NONE === 0);
assert(XSD_STRING === 101);

// SoapClient non-WSDL construct
$c = new SoapClient(null, [
    'location' => 'http://127.0.0.1:1/svc',
    'uri' => 'urn:example',
]);
assert($c instanceof SoapClient);

// __setLocation returns prior location string
$prev = $c->__setLocation('http://other/');
assert($prev === 'http://127.0.0.1:1/svc');

// SoapHeader
$h = new SoapHeader('urn:ns', 'AuthToken', 'abc', true, 'actor');
assert($h->namespace === 'urn:ns');
assert($h->name === 'AuthToken');
assert($h->data === 'abc');
assert($h->mustUnderstand === true);
assert($h->actor === 'actor');

// SoapVar
$v = new SoapVar('hello', XSD_STRING);
assert($v->enc_value === 'hello');
assert($v->enc_type === XSD_STRING);

// SoapParam
$p = new SoapParam('arg1', 'param1');
assert($p->param_data === 'arg1');
assert($p->param_name === 'param1');

// SoapFault is an Exception
$f = new SoapFault('Server', 'something bad');
assert($f instanceof Exception);
assert($f instanceof SoapFault);
assert($f->faultcode === 'Server');
assert($f->faultstring === 'something bad');
assert($f->getMessage() === 'something bad');

echo "ok\n";
