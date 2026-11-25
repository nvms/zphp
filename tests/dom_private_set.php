<?php
// php 8.6 declares the DOM properties it documented as readonly
// `public private(set)`: writes from outside are a visibility error

$doc = new DOMDocument();
$doc->loadXML('<?xml version="1.0" encoding="UTF-8"?><r a="1"><c>t</c><?pi data?><!--x--><![CDATA[cd]]></r>');
$r = $doc->documentElement;
$x = new DOMXPath($doc);

function attempt(string $label, callable $f): void {
    try {
        $f();
        echo "$label: ok\n";
    } catch (Throwable $e) {
        echo "$label: ", $e::class, ': ', $e->getMessage(), "\n";
    }
}

attempt('DOMElement nodeType', function () use ($r) { $r->nodeType = 3; });
attempt('DOMElement nodeName', function () use ($r) { $r->nodeName = 'x'; });
attempt('DOMElement tagName', function () use ($r) { $r->tagName = 'x'; });
attempt('DOMElement parentNode', function () use ($r) { $r->parentNode = null; });
attempt('DOMElement firstElementChild', function () use ($r) { $r->firstElementChild = null; });
attempt('DOMElement childElementCount', function () use ($r) { $r->childElementCount = 0; });
attempt('DOMDocument nodeType', function () use ($doc) { $doc->nodeType = 1; });
attempt('DOMDocument xmlEncoding', function () use ($doc) { $doc->xmlEncoding = 'x'; });
attempt('DOMDocument actualEncoding', function () use ($doc) { $doc->actualEncoding = 'x'; });
attempt('DOMDocument documentElement', function () use ($doc) { $doc->documentElement = null; });
attempt('DOMDocument doctype', function () use ($doc) { $doc->doctype = null; });
attempt('DOMNodeList length', function () use ($r) { $r->childNodes->length = 3; });
attempt('DOMNodeList length, query', function () use ($x) { $l = $x->query('//c'); $l->length = 3; });
attempt('DOMNodeList length, by tag', function () use ($doc) { $l = $doc->getElementsByTagName('c'); $l->length = 3; });
attempt('DOMNamedNodeMap length', function () use ($r) { $r->attributes->length = 1; });
attempt('DOMXPath document', function () use ($x) { $x->document = null; });
attempt('DOMText wholeText', function () use ($r) { $r->firstChild->firstChild->wholeText = 'w'; });
attempt('DOMText length', function () use ($r) { $r->firstChild->firstChild->length = 1; });
attempt('DOMProcessingInstruction target', function () use ($r) { $r->childNodes[1]->target = 't'; });
attempt('DOMComment length', function () use ($r) { $r->childNodes[2]->length = 1; });
attempt('DOMCdataSection wholeText', function () use ($r) { $r->childNodes[3]->wholeText = 1; });
attempt('DOMAttr name', function () use ($r) { $r->getAttributeNode('a')->name = 'b'; });
attempt('DOMAttr ownerElement', function () use ($r) { $r->getAttributeNode('a')->ownerElement = null; });
attempt('DOMDocumentFragment childElementCount', function () use ($doc) { $f = $doc->createDocumentFragment(); $f->childElementCount = 1; });
attempt('increment', function () use ($r) { $r->nodeType++; });
attempt('compound', function () use ($r) { $r->nodeName .= 'x'; });

// what stays writable
attempt('DOMAttr value', function () use ($r) { $r->getAttributeNode('a')->value = 'z'; });
attempt('DOMElement nodeValue', function () use ($r) { $r->firstChild->nodeValue = 'u'; });
attempt('DOMDocument xmlVersion', function () use ($doc) { $doc->xmlVersion = '1.0'; });
echo $r->getAttribute('a'), ' ', $r->firstChild->textContent, "\n";

class Sub extends DOMElement {
    public function setTagName(): void { $this->tagName = 'q'; }
    public function setNodeType(): void { $this->nodeType = 1; }
}
attempt('subclass tagName', function () { (new Sub('a'))->setTagName(); });
attempt('subclass nodeType', function () { (new Sub('a'))->setNodeType(); });
attempt('subclass from outside', function () { $e = new Sub('a'); $e->tagName = 'b'; });

// a property php's DOM doesn't declare is a dynamic one
$doc->foo = 1;
$r->foo = 2;
$r->foo = 3;
$l = $r->childNodes;
$l->foo = 4;
$x->foo = 5;
var_dump($doc->foo, $r->foo, $l->foo, $x->foo, $l->length, $r->attributes->length);
print_r($doc->getElementsByTagName('c'));
echo "\n";
