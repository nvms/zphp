<?php
// covers: SimpleXML parsing, magic property access, attribute access, iteration, xpath, mutation, toString

$xml = <<<XML
<?xml version="1.0"?>
<library>
    <book id="1" genre="fiction">
        <title>The Hobbit</title>
        <author>J.R.R. Tolkien</author>
    </book>
    <book id="2" genre="science">
        <title>A Brief History of Time</title>
        <author>Stephen Hawking</author>
    </book>
</library>
XML;

$root = simplexml_load_string($xml);

echo "root name: ", $root->getName(), "\n";
echo "book count: ", count($root->book), "\n";

foreach ($root->book as $book) {
    echo "- ", (string)$book['id'], " [", (string)$book['genre'], "] ",
         (string)$book->title, " / ", (string)$book->author, "\n";
}

// xpath
$matches = $root->xpath('//book[@genre="fiction"]');
echo "xpath fiction: ", count($matches), "\n";
foreach ($matches as $m) {
    echo "  ", (string)$m->title, "\n";
}

// addChild + addAttribute
$root->addChild('book');
$last = $root->book[2];
$last->addChild('title', 'Foundation');
$last->addChild('author', 'Isaac Asimov');
$last->addAttribute('id', '3');
$last->addAttribute('genre', 'fiction');

echo "after add: ", count($root->book), "\n";
echo "last title: ", (string)$last->title, "\n";
echo "last attr id: ", (string)$last['id'], "\n";

// attributes() iteration
foreach ($root->book[0]->attributes() as $k => $v) {
    echo "attr $k = ", (string)$v, "\n";
}

// xpath with namespaces
$nsXml = '<?xml version="1.0"?><ns:root xmlns:ns="http://example.com/ns"><ns:item>n1</ns:item><ns:item>n2</ns:item></ns:root>';
$nsRoot = simplexml_load_string($nsXml);
$nsRoot->registerXPathNamespace('e', 'http://example.com/ns');
$items = $nsRoot->xpath('//e:item');
echo "ns items: ", count($items), "\n";
foreach ($items as $i) {
    echo "  ns item: ", (string)$i, "\n";
}

// offsetExists for attribute
echo "has id: ", isset($root->book[0]['id']) ? "yes" : "no", "\n";
echo "has nope: ", isset($root->book[0]['nope']) ? "yes" : "no", "\n";

// getNamespaces
$nsArr = $nsRoot->getNamespaces();
foreach ($nsArr as $k => $v) {
    echo "ns: '$k' -> $v\n";
}

// asXML round trip
echo $root->asXML();
