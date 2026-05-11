<?php
// covers: SimpleXML with namespaces, registerXPathNamespace, children() with ns,
//   attribute access, DOMDocument round-trip, namespaced XPath queries

$xml = <<<XML
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns="http://www.w3.org/2005/Atom"
     xmlns:dc="http://purl.org/dc/elements/1.1/"
     xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <title>Feed Title</title>
  <updated>2026-05-11T10:00:00Z</updated>
  <entry>
    <title>First Post</title>
    <dc:creator>Alice</dc:creator>
    <content:encoded>full text here</content:encoded>
    <link href="https://example.com/1" rel="alternate"/>
  </entry>
  <entry>
    <title>Second Post</title>
    <dc:creator>Bob</dc:creator>
    <content:encoded>more content</content:encoded>
    <link href="https://example.com/2" rel="alternate"/>
  </entry>
</rss>
XML;

echo "=== SimpleXML basic load ===\n";
$sx = simplexml_load_string($xml);
echo "root name: " . $sx->getName() . "\n";
echo "title (default ns): " . $sx->title . "\n";

echo "\n=== children in default namespace ===\n";
$atom_ns = 'http://www.w3.org/2005/Atom';
$entries = $sx->children($atom_ns);
$count = 0;
foreach ($entries->entry as $e) {
    echo "entry title: " . $e->title . "\n";
    $count++;
}
echo "entries found: $count\n";

echo "\n=== children with prefixed namespace ===\n";
$dc_ns = 'http://purl.org/dc/elements/1.1/';
foreach ($sx->entry as $entry) {
    $dc = $entry->children($dc_ns);
    echo "creator: " . $dc->creator . "\n";
}

echo "\n=== content:encoded via namespace ===\n";
$content_ns = 'http://purl.org/rss/1.0/modules/content/';
foreach ($sx->entry as $entry) {
    $content = $entry->children($content_ns);
    echo "encoded: " . trim($content->encoded) . "\n";
}

echo "\n=== attribute access ===\n";
foreach ($sx->entry as $entry) {
    echo "link href: " . (string)$entry->link['href'] . "\n";
    echo "link rel:  " . (string)$entry->link['rel'] . "\n";
}

echo "\n=== XPath with namespaces ===\n";
$sx->registerXPathNamespace('a', $atom_ns);
$sx->registerXPathNamespace('d', $dc_ns);
$titles = $sx->xpath('//a:entry/a:title');
foreach ($titles as $t) echo "xpath title: " . (string)$t . "\n";

$creators = $sx->xpath('//d:creator');
foreach ($creators as $c) echo "xpath creator: " . (string)$c . "\n";

echo "\n=== DOM round-trip ===\n";
$dom = new DOMDocument();
$dom->loadXML($xml);
$root = $dom->documentElement;
echo "dom root: " . $root->nodeName . "\n";
echo "dom entries: " . $root->getElementsByTagNameNS($atom_ns, 'entry')->length . "\n";

$xpath = new DOMXPath($dom);
$xpath->registerNamespace('a', $atom_ns);
$xpath->registerNamespace('d', $dc_ns);
$result = $xpath->query('//d:creator');
echo "DOMXPath creators:\n";
foreach ($result as $node) echo "  " . $node->nodeValue . "\n";

echo "\n=== add element via DOM ===\n";
$new_entry = $dom->createElementNS($atom_ns, 'entry');
$new_title = $dom->createElementNS($atom_ns, 'title', 'Third Post');
$new_entry->appendChild($new_title);
$root->appendChild($new_entry);

$after = $xpath->query('//a:entry/a:title');
echo "titles now:\n";
foreach ($after as $t) echo "  " . $t->nodeValue . "\n";
