<?php
// covers: DOMDocument mutation - createElement/Text, appendChild, insertBefore,
//   removeChild, replaceChild, attribute manipulation, normalizing whitespace,
//   saveXML/HTML, cloning, walk-and-edit pattern

$dom = new DOMDocument('1.0', 'UTF-8');
$dom->formatOutput = false;

echo "=== build a document programmatically ===\n";
$root = $dom->createElement('catalog');
$dom->appendChild($root);

foreach ([['Book A', '14.99'], ['Book B', '9.50'], ['Book C', '21.00']] as $i => [$title, $price]) {
    $item = $dom->createElement('item');
    $item->setAttribute('id', (string)($i + 1));
    $t = $dom->createElement('title', $title);
    $p = $dom->createElement('price', $price);
    $item->appendChild($t);
    $item->appendChild($p);
    $root->appendChild($item);
}

$xml = $dom->saveXML();
echo "rendered length: " . strlen($xml) . "\n";
echo "starts with prolog: " . (str_starts_with($xml, '<?xml') ? "yes" : "no") . "\n";

echo "\n=== query and read ===\n";
$items = $dom->getElementsByTagName('item');
echo "item count: " . $items->length . "\n";
foreach ($items as $it) {
    echo "  id=" . $it->getAttribute('id') . " title=" . $it->getElementsByTagName('title')->item(0)->nodeValue . "\n";
}

echo "\n=== insertBefore ===\n";
$first = $items->item(0);
$header = $dom->createElement('header', 'inserted');
$root->insertBefore($header, $first);
echo "first child name: " . $root->firstChild->nodeName . "\n";

echo "\n=== removeChild ===\n";
$root->removeChild($header);
echo "after remove, first child: " . $root->firstChild->nodeName . "\n";

echo "\n=== replaceChild ===\n";
$old = $items->item(1);
$new = $dom->createElement('replacement');
$new->setAttribute('marker', 'yes');
$root->replaceChild($new, $old);
echo "replaced node attr: " . $new->getAttribute('marker') . "\n";
echo "item count after replace: " . $dom->getElementsByTagName('item')->length . "\n";

echo "\n=== attribute lifecycle ===\n";
$first = $dom->getElementsByTagName('item')->item(0);
$first->setAttribute('discount', '0.10');
echo "has discount: " . ($first->hasAttribute('discount') ? "yes" : "no") . "\n";
$first->setAttribute('discount', '0.15');
echo "discount value: " . $first->getAttribute('discount') . "\n";
$first->removeAttribute('discount');
echo "after remove: " . ($first->hasAttribute('discount') ? "yes" : "no") . "\n";

echo "\n=== createTextNode and adjacency ===\n";
$wrapper = $dom->createElement('note');
$wrapper->appendChild($dom->createTextNode("part one "));
$wrapper->appendChild($dom->createTextNode("part two"));
$root->appendChild($wrapper);
echo "text content: " . $wrapper->nodeValue . "\n";

echo "\n=== clone shallow vs deep ===\n";
$tmpl = $dom->createElement('row');
$tmpl->setAttribute('class', 'tmpl');
$tmpl->appendChild($dom->createElement('cell', 'A'));
$tmpl->appendChild($dom->createElement('cell', 'B'));

$shallow = $tmpl->cloneNode(false);
$deep = $tmpl->cloneNode(true);
echo "shallow children: " . $shallow->childNodes->length . "\n";
echo "deep children: " . $deep->childNodes->length . "\n";
echo "deep keeps attr: " . $deep->getAttribute('class') . "\n";

echo "\n=== walk and mutate ===\n";
$dom2 = new DOMDocument();
$dom2->loadXML('<root><a>1</a><b>2</b><a>3</a><a>4</a></root>');
$as = $dom2->getElementsByTagName('a');
// snapshot to avoid live-list mutation issues
$snapshot = [];
foreach ($as as $n) $snapshot[] = $n;
foreach ($snapshot as $n) $n->nodeValue = '[' . $n->nodeValue . ']';
$out = $dom2->saveXML($dom2->documentElement);
echo "after mutate: $out\n";

echo "\n=== removeChild loop ===\n";
$dom3 = new DOMDocument();
$dom3->loadXML('<r><x/><y/><z/></r>');
$root3 = $dom3->documentElement;
while ($root3->firstChild) $root3->removeChild($root3->firstChild);
echo "remaining children: " . $root3->childNodes->length . "\n";

echo "\n=== importNode across documents ===\n";
$src = new DOMDocument();
$src->loadXML('<source><foo>hi</foo><foo>bye</foo></source>');
$dst = new DOMDocument();
$dst->appendChild($dst->createElement('dest'));

foreach ($src->getElementsByTagName('foo') as $node) {
    $copy = $dst->importNode($node, true);
    $dst->documentElement->appendChild($copy);
}
echo "dst child count: " . $dst->documentElement->childNodes->length . "\n";
echo $dst->saveXML($dst->documentElement) . "\n";

echo "\ndone\n";
