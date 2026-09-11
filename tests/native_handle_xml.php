<?php
// covers: DOM/SimpleXML/XMLReader/XMLWriter keep working when a script writes the old pointer property names, clone semantics per class

$xml = '<?xml version="1.0"?>' . "\n" . '<root><item id="1">one</item><item id="2">two</item></root>' . "\n";

// ---- DOMDocument ----
$doc = new DOMDocument();
$doc->__node = 0x41414141;
$doc->loadXML($xml);
echo "doc: ", $doc->documentElement->nodeName, " ", $doc->getElementsByTagName('item')->length, "\n";
var_dump(isset($doc->__node));

$docCopy = clone $doc;
$docCopy->documentElement->appendChild($docCopy->createElement('added', 'x'));
echo "orig items: ", $doc->getElementsByTagName('added')->length, "\n";
echo "copy items: ", $docCopy->getElementsByTagName('added')->length, "\n";
echo "copy owner is copy: ", var_export($docCopy->documentElement->ownerDocument === $docCopy, true), "\n";
echo $docCopy->saveXML();

// ---- DOMElement ----
$el = $doc->documentElement->firstChild;
$el->__node = 0x41414141;
echo "el: ", $el->nodeName, " ", $el->getAttribute('id'), " ", $el->textContent, "\n";
var_dump(isset($el->__node));

$elCopy = clone $el;
$elCopy->setAttribute('id', '9');
echo "orig id: ", $el->getAttribute('id'), "\n";
echo "copy id: ", $elCopy->getAttribute('id'), "\n";
echo "copy detached: ", var_export($elCopy->parentNode === null, true), "\n";
echo "copy owner: ", var_export($elCopy->ownerDocument === $doc, true), "\n";
$doc->documentElement->appendChild($elCopy);
echo "after append: ", $doc->getElementsByTagName('item')->length, "\n";

// ---- DOMText / DOMComment / DOMAttr ----
$text = $el->firstChild;
$text->__node = 0x41414141;
$textCopy = clone $text;
$textCopy->data = 'changed';
echo "text: ", $text->data, " / ", $textCopy->data, "\n";

$comment = $doc->createComment('note');
$comment->__node = 0x41414141;
$commentCopy = clone $comment;
echo "comment: ", $commentCopy->data, " ", $commentCopy->nodeName, "\n";

$attr = $el->getAttributeNode('id');
$attr->__node = 0x41414141;
$attrCopy = clone $attr;
echo "attr: ", $attrCopy->name, "=", $attrCopy->value, "\n";

// ---- SimpleXMLElement ----
$sx = simplexml_load_string($xml);
$sx->__node = 'n';
$sx->__doc = 'd';
$sx->__owns_doc = 'o';
$sx->__cursor = 'c';
echo "sx: ", $sx->getName(), " ", count($sx->item), " ", (string) $sx->item[1], "\n";
var_dump(isset($sx->__node));
echo "sx children: ";
foreach ($sx->children() as $name => $child) echo $name, ",";
echo "\n";

$sxCopy = clone $sx;
$sxCopy->addChild('added', 'v');
echo "orig added: ", var_export(isset($sx->added), true), "\n";
echo "copy added: ", var_export(isset($sxCopy->added), true), " ", (string) $sxCopy->added, "\n";
echo "copy name: ", $sxCopy->getName(), "\n";
echo $sxCopy->asXML(), "\n";

$itemCopy = clone $sx->item[0];
$itemCopy['id'] = '7';
echo "item ids: ", (string) $sx->item[0]['id'], " / ", (string) $itemCopy['id'], "\n";

// ---- SimpleXMLIterator ----
$it = new SimpleXMLIterator('<list><a>1</a><b>2</b><c><d>3</d></c></list>');
$it->__cursor = 'c';
$it->__node = 'n';
echo "iter: ";
foreach ($it as $k => $v) echo $k, "=", trim((string) $v), ";";
echo "\n";
echo "iter leaves: ";
foreach (new RecursiveIteratorIterator($it) as $k => $v) echo $k, "=", (string) $v, ";";
echo "\n";
var_dump(isset($it->__cursor));

$itCopy = clone $it;
$itCopy->addChild('e', '4');
echo "iter copy: ";
foreach ($itCopy as $k => $v) echo $k, ";";
echo "\n";
echo "iter orig count: ", count($it->children()), "\n";

// ---- XMLReader ----
$reader = XMLReader::XML($xml);
$reader->__reader = 0x41414141;
$names = [];
while ($reader->read()) {
    if ($reader->nodeType === XMLReader::ELEMENT) $names[] = $reader->name;
}
echo "reader: ", implode(',', $names), "\n";
var_dump(isset($reader->__reader));
$reader->close();

$reader2 = XMLReader::XML('<r><x a="1">t</x></r>');
$reader2->read();
$reader2->read();
$expanded = $reader2->expand();
echo "expand: ", $expanded->nodeName, " ", $expanded->getAttribute('a'), " ", $expanded->textContent, "\n";
$imported = simplexml_import_dom($doc->documentElement);
echo "import: ", $imported->getName(), " ", count($imported->item), "\n";

try {
    $r = clone $reader2;
    echo "reader cloned\n";
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

// ---- XMLWriter ----
$writer = new XMLWriter();
$writer->openMemory();
$writer->__writer = 0x41414141;
$writer->__buffer = 0x42424242;
$writer->startElement('w');
$writer->writeAttribute('k', 'v');
$writer->text('body');
$writer->endElement();
echo "writer: ", $writer->outputMemory(), "\n";
var_dump(isset($writer->__writer));

try {
    $w = clone $writer;
    echo "writer cloned\n";
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
