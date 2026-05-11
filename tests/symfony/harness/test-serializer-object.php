<?php
// exercises symfony/serializer ObjectNormalizer + reflection-based type coercion.
// stresses constructor argument matching, getter/setter discovery, and the
// PropertyInfo type extractor (heavy reflection use)
require __DIR__ . '/../app/vendor/autoload.php';

use Symfony\Component\Serializer\Serializer;
use Symfony\Component\Serializer\Normalizer\ObjectNormalizer;
use Symfony\Component\Serializer\Normalizer\ArrayDenormalizer;
use Symfony\Component\Serializer\Encoder\JsonEncoder;
use Symfony\Component\Serializer\Encoder\XmlEncoder;

class Book {
    public function __construct(
        public readonly string $title,
        public readonly string $author,
        public readonly int $year,
        public ?array $tags = null,
    ) {}
}

class Library {
    /** @var Book[] */
    public array $books = [];
    public string $name;
}

$serializer = new Serializer(
    [new ArrayDenormalizer(), new ObjectNormalizer()],
    [new JsonEncoder(), new XmlEncoder()],
);

// normalize object -> array
$book = new Book('Dune', 'Herbert', 1965, ['scifi', 'classic']);
$arr = $serializer->normalize($book, 'array');
ksort($arr);
foreach ($arr as $k => $v) {
    if (is_array($v)) $v = implode(',', $v);
    if ($v === null) $v = 'null';
    echo "$k=$v\n";
}

// normalize -> json -> denormalize
$json = $serializer->serialize($book, 'json');
echo "json: $json\n";

$back = $serializer->deserialize($json, Book::class, 'json');
echo "back: ", $back->title, " by ", $back->author, " (", $back->year, ")\n";
echo "tags: ", $back->tags ? implode(',', $back->tags) : 'NONE', "\n";

// nested with array of objects
$lib = new Library();
$lib->name = 'Home';
$lib->books = [
    new Book('A', 'X', 2000),
    new Book('B', 'Y', 2010),
];
$json2 = $serializer->serialize($lib, 'json');
echo "lib json: $json2\n";

// xml
$xml = $serializer->serialize($book, 'xml', ['xml_root_node_name' => 'book']);
echo $xml, "\n";
