<?php
// exercises symfony/css-selector - CSS-to-XPath conversion. dense string
// parsing, tokenization, regex, and the visitor pattern over the parsed tree
require __DIR__ . '/../app/vendor/autoload.php';

use Symfony\Component\CssSelector\CssSelectorConverter;

$c = new CssSelectorConverter();
$selectors = [
    'div',
    'div.foo',
    'a#bar',
    'ul > li',
    'ul li',
    'h1 + p',
    'h1 ~ p',
    'input[type="text"]',
    'a[href]',
    'a[href^="http"]',
    'a[href$=".pdf"]',
    'a[href*="example"]',
    'p:first-child',
    'p:last-child',
    'li:nth-child(2)',
    'li:nth-child(odd)',
    'a:not(.external)',
    'div p span',
    '*',
    '.a.b.c',
    'div > p.intro:first-child',
];
foreach ($selectors as $sel) {
    echo $sel, ' => ', $c->toXPath($sel), "\n";
}

// HTML vs XML mode prefix
$cx = new CssSelectorConverter(false);
echo "xml-mode: ", $cx->toXPath('Foo > Bar'), "\n";
