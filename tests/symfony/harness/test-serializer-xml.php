<?php
// exercises symfony/serializer XmlEncoder -> DOMDocument writes
require __DIR__ . '/../app/vendor/autoload.php';

use Symfony\Component\Serializer\Encoder\XmlEncoder;

$enc = new XmlEncoder();

// array -> xml
$data = [
    'title' => 'Hello',
    'tags' => ['php', 'xml', 'zphp'],
    'meta' => [
        'created' => '2026-05-11',
        'count' => 42,
    ],
    'desc' => '<unsafe & content>',
];

$xml = $enc->encode($data, 'xml', ['xml_root_node_name' => 'doc']);
echo $xml, "\n";

// round trip: xml -> array
$back = $enc->decode($xml, 'xml');
echo "decoded keys: ", implode(',', array_keys($back)), "\n";
echo "title: ", $back['title'], "\n";
echo "tag0: ", $back['tags']['tag'][0] ?? ($back['tags']['tag'] ?? 'NONE'), "\n";
echo "count: ", $back['meta']['count'], "\n";
echo "desc: ", $back['desc'], "\n";

// formatted output
$xml2 = $enc->encode($data, 'xml', [
    'xml_root_node_name' => 'doc',
    'xml_format_output' => true,
]);
echo $xml2;
