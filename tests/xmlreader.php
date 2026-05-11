<?php
// covers: XMLReader streaming, attribute access, depth/nodeType, readInnerXml/readOuterXml

$xml = <<<XML
<?xml version="1.0"?>
<feed>
    <entry id="1"><title>One</title></entry>
    <entry id="2"><title>Two</title></entry>
    <entry id="3"><title>Three</title></entry>
</feed>
XML;

$r = XMLReader::XML($xml);
$count = 0;
while ($r->read()) {
    if ($r->nodeType === XMLReader::ELEMENT && $r->name === 'entry') {
        $count++;
        echo "entry depth=", $r->depth, " id=", $r->getAttribute('id'), "\n";
    }
}
echo "entries: $count\n";

$r->close();

// streaming via instance construction + open with a temp file
$tmp = tempnam(sys_get_temp_dir(), 'xr');
file_put_contents($tmp, $xml);
$r2 = new XMLReader();
$r2->open($tmp);
while ($r2->read()) {
    if ($r2->nodeType === XMLReader::ELEMENT && $r2->name === 'title') {
        echo "title: ", $r2->readString(), "\n";
    }
}
$r2->close();
unlink($tmp);

// readOuterXml / readInnerXml
$r3 = XMLReader::XML($xml);
while ($r3->read()) {
    if ($r3->nodeType === XMLReader::ELEMENT && $r3->name === 'entry' && $r3->getAttribute('id') === '2') {
        echo "outer: ", trim($r3->readOuterXml()), "\n";
        break;
    }
}
$r3->close();

// attributes loop
$r4 = XMLReader::XML('<r a="1" b="2" c="3"/>');
while ($r4->read()) {
    if ($r4->nodeType === XMLReader::ELEMENT) {
        echo "attr count: ", $r4->attributeCount, "\n";
        if ($r4->moveToFirstAttribute()) {
            do {
                echo "  ", $r4->name, "=", $r4->value, "\n";
            } while ($r4->moveToNextAttribute());
        }
        break;
    }
}
$r4->close();
