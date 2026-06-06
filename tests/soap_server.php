<?php
// covers: SoapServer non-WSDL dispatch (setClass/setObject/addFunction),
// scalar return type encoding (int/float/bool/string/null), arg parsing,
// XML entity escape/unescape

class Calc {
    private $base = 100;
    public function add($a, $b) { return $a + $b; }
    public function sub($a, $b) { return $a - $b; }
    public function withBase($x) { return $this->base + $x; }
    public function name() { return "Calc & Co <v1>"; }
    public function ratio() { return 3.5; }
    public function ok() { return true; }
    public function no() { return false; }
    public function nothing() { return null; }
}

function envelope($uri, $method, $argsXml) {
    return '<?xml version="1.0" encoding="UTF-8"?>'
        . '<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns1="' . $uri . '">'
        . '<SOAP-ENV:Body><ns1:' . $method . '>' . $argsXml . '</ns1:' . $method . '></SOAP-ENV:Body>'
        . '</SOAP-ENV:Envelope>';
}

// collect all output and echo once at the end - calling handle() while output
// has already been flushed makes PHP warn "headers already sent", which zphp
// (no header layer here) would not emit, so never flush until the very end
function call($server, $uri, $method, $argsXml) {
    ob_start();
    $server->handle(envelope($uri, $method, $argsXml));
    return ob_get_clean();
}

$out = '';

// setClass dispatch
$s = new SoapServer(null, ['uri' => 'urn:calc']);
$s->setClass('Calc');
$out .= call($s, 'urn:calc', 'add', '<a>3</a><b>4</b>');
$out .= call($s, 'urn:calc', 'sub', '<a>10</a><b>4</b>');
$out .= call($s, 'urn:calc', 'withBase', '<x>5</x>');
$out .= call($s, 'urn:calc', 'name', '');
$out .= call($s, 'urn:calc', 'ratio', '');
$out .= call($s, 'urn:calc', 'ok', '');
$out .= call($s, 'urn:calc', 'no', '');
$out .= call($s, 'urn:calc', 'nothing', '');

// setObject dispatch (instance state preserved across calls)
$obj = new Calc();
$s2 = new SoapServer(null, ['uri' => 'urn:c2']);
$s2->setObject($obj);
$out .= call($s2, 'urn:c2', 'add', '<a>20</a><b>22</b>');
$out .= call($s2, 'urn:c2', 'name', '');

// string arg with entities (escaped in, unescaped for dispatch, re-escaped out)
class Echoer {
    public function repeat($s) { return $s . $s; }
}
$s3 = new SoapServer(null, ['uri' => 'urn:echo']);
$s3->setObject(new Echoer());
$out .= call($s3, 'urn:echo', 'repeat', '<s>a &lt; b &amp; c</s>');

// addFunction dispatch
function multiply($a, $b) { return $a * $b; }
$s4 = new SoapServer(null, ['uri' => 'urn:fn']);
$s4->addFunction('multiply');
$out .= call($s4, 'urn:fn', 'multiply', '<a>6</a><b>7</b>');

echo $out;
