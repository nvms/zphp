<?php
// exercises symfony/string AsciiSlugger -> Transliterator
require __DIR__ . '/../app/vendor/autoload.php';

use Symfony\Component\String\Slugger\AsciiSlugger;

$slugger = new AsciiSlugger();

$inputs = [
    "Hello World",
    "café résumé",
    "Москва",
    "東京",
    "1 + 2 = 3",
    "Über Größe",
    "naïve façade",
];

foreach ($inputs as $in) {
    echo $in, " -> ", $slugger->slug($in), "\n";
}

// with explicit locale + separator
echo "de: ", $slugger->slug("Größe Mädchen", "_", "de"), "\n";
echo "explicit: ", $slugger->slug("Hello   World!!", "-"), "\n";
