<?php
// a SimpleXMLElement is false when what it stands for is empty: the document
// element without attributes, child elements or text, an empty children() or
// attributes() list

$docs = [
    '<root></root>', '<root/>', '<root>  </root>', '<root>text</root>', '<root a="1"/>',
    '<root><a/></root>', '<root><a/><b>x</b></root>', '<root><![CDATA[c]]></root>',
    '<root xmlns:p="urn:p"><p:x/></root>', '<root><!-- c --></root>',
];
foreach ($docs as $xml) {
    $x = simplexml_load_string($xml);
    echo str_pad($xml, 40), json_encode([
        (bool) $x,
        (bool) $x->children(),
        (bool) $x->attributes(),
        (bool) $x->a,
        (bool) $x->b,
        (bool) $x->children('urn:p'),
        $x ? 'if' : 'else',
        !$x,
    ]), "\n";
}

$x = simplexml_load_string('<root a="1"><item/><item>2</item></root>');
foreach ($x->item as $item) {
    var_dump((bool) $item);
}
var_dump((bool) $x['a'], (bool) $x['missing'], (bool) $x->item[0], (bool) $x->item[1]);
var_dump((bool) new SimpleXMLElement('<e/>'), (bool) new SimpleXMLElement('<e>1</e>'));
