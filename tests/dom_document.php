<?php
// covers: DOMDocument parsing, navigation, getElementsByTagName, attributes, xpath, creation, serialization

$xml = <<<XML
<?xml version="1.0"?>
<library>
    <book id="1" genre="fiction">
        <title>The Hobbit</title>
        <author>J.R.R. Tolkien</author>
        <year>1937</year>
    </book>
    <book id="2" genre="science">
        <title>A Brief History of Time</title>
        <author>Stephen Hawking</author>
        <year>1988</year>
    </book>
    <book id="3" genre="fiction">
        <title>Dune</title>
        <author>Frank Herbert</author>
        <year>1965</year>
    </book>
</library>
XML;

$doc = new DOMDocument();
$doc->loadXML($xml);

echo "root: ", $doc->documentElement->nodeName, "\n";
echo "doc nodeType: ", $doc->nodeType, "\n";
echo "element nodeType: ", $doc->documentElement->nodeType, "\n";

$books = $doc->getElementsByTagName('book');
echo "book count: ", $books->length, "\n";
echo "count()  : ", count($books), "\n";

foreach ($books as $book) {
    echo "- id=", $book->getAttribute('id'),
         " genre=", $book->getAttribute('genre'),
         " title=", $book->getElementsByTagName('title')->item(0)->nodeValue,
         " year=", $book->getElementsByTagName('year')->item(0)->textContent,
         "\n";
}

echo "has genre on book[0]: ", $books->item(0)->hasAttribute('genre') ? "yes" : "no", "\n";
echo "has missing on book[0]: ", $books->item(0)->hasAttribute('missing') ? "yes" : "no", "\n";

// xpath
$xp = new DOMXPath($doc);
$fiction = $xp->query('//book[@genre="fiction"]');
echo "fiction books: ", $fiction->length, "\n";
foreach ($fiction as $b) {
    echo "  fiction: ", $b->getElementsByTagName('title')->item(0)->nodeValue, "\n";
}

// evaluate scalar
$count = $xp->evaluate('count(//book)');
echo "evaluated count: ", $count, "\n";

// element children walk
$first = $doc->documentElement->firstChild;
echo "first child type: ", $first->nodeType, "\n"; // text (whitespace)
$firstEl = $doc->getElementsByTagName('book')->item(0);
echo "first book parent: ", $firstEl->parentNode->nodeName, "\n";

// creation + appendChild
$doc2 = new DOMDocument('1.0', 'UTF-8');
$root = $doc2->createElement('catalog');
$doc2->appendChild($root);
$item = $doc2->createElement('item', 'first');
$item->setAttribute('name', 'A');
$root->appendChild($item);
$item2 = $doc2->createElement('item');
$item2->appendChild($doc2->createTextNode('second'));
$item2->setAttribute('name', 'B');
$root->appendChild($item2);
echo $doc2->saveXML();

// removeAttribute
$item->removeAttribute('name');
echo "after remove, has name: ", $item->hasAttribute('name') ? "yes" : "no", "\n";

// cloneNode
$clone = $item2->cloneNode(true);
echo "clone tag: ", $clone->tagName, " name=", $clone->getAttribute('name'), "\n";
echo "clone parent: ", $clone->parentNode === null ? "null" : "not null", "\n";

// removeChild
$root->removeChild($item2);
echo "after remove, root children count: ", $root->childNodes->length, "\n";

// substringData on a text node
$txt = $doc2->createTextNode('hello world');
echo "substring: ", $txt->substringData(6, 5), "\n";

// namespace
$nsXml = '<?xml version="1.0"?><ns:root xmlns:ns="http://example.com/ns"><ns:item>n1</ns:item></ns:root>';
$nsDoc = new DOMDocument();
$nsDoc->loadXML($nsXml);
$xpns = new DOMXPath($nsDoc);
$xpns->registerNamespace('e', 'http://example.com/ns');
$found = $xpns->query('//e:item');
echo "ns query: ", $found->length, " -> ", $found->item(0)->nodeValue, "\n";

// xpath string
$str = $xp->evaluate('string(//book[1]/title)');
echo "xpath string: ", $str, "\n";

// bool
$b = $xp->evaluate('count(//book) > 2');
echo "xpath bool: ", $b ? "true" : "false", "\n";
