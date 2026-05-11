<?php
// exercises symfony/dom-crawler -> DOMDocument + DOMXPath + symfony/css-selector
require __DIR__ . '/../app/vendor/autoload.php';

use Symfony\Component\DomCrawler\Crawler;

$html = <<<HTML
<!DOCTYPE html>
<html>
<body>
  <article class="post" data-id="1">
    <h2>First post</h2>
    <p class="content">hello <em>world</em></p>
    <ul>
      <li class="tag">php</li>
      <li class="tag">xml</li>
    </ul>
  </article>
  <article class="post" data-id="2">
    <h2>Second post</h2>
    <p class="content">another body</p>
  </article>
</body>
</html>
HTML;

// pass useHtml5Parser=false to take the legacy DOMDocument::loadHTML path.
// PHP 8.4's Dom\HTMLDocument isn't implemented yet (see roadmap)
@$crawler = new Crawler($html, null, null, false);

echo "articles: ", $crawler->filter('article')->count(), "\n";
echo "first h2: ", $crawler->filter('article h2')->first()->text(), "\n";
echo "tags: ", $crawler->filter('li.tag')->count(), "\n";

foreach ($crawler->filter('li.tag') as $node) {
    echo "  tag: ", $node->nodeValue, "\n";
}

// attribute access
foreach ($crawler->filter('article.post') as $node) {
    echo "  id: ", $node->getAttribute('data-id'), "\n";
}

// xpath
$xp = $crawler->filterXPath('//article[@data-id="2"]/h2');
echo "xpath h2: ", $xp->text(), "\n";

// extract
$ids = $crawler->filter('article')->extract(['data-id']);
echo "extracted: ", implode(',', array_map(fn($r) => $r[0], $ids)), "\n";

// chained content extraction
$contents = $crawler->filter('p.content')->each(fn($node) => trim($node->text()));
echo "contents: ", implode(' | ', $contents), "\n";
