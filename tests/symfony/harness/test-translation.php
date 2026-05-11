<?php
// exercises symfony/translation - catalog loading + basic placeholder
// substitution. ICU MessageFormat is the harder path - try both
require __DIR__ . '/../app/vendor/autoload.php';

use Symfony\Component\Translation\Translator;
use Symfony\Component\Translation\Loader\ArrayLoader;

$t = new Translator('en');
$t->addLoader('array', new ArrayLoader());
$t->addResource('array', [
    'hello' => 'Hello!',
    'greet' => 'Hi, %name%!',
    'cart.items' => '{0} Your cart is empty|{1} You have one item|]1,Inf[ You have %count% items',
], 'en');
$t->addResource('array', [
    'hello' => 'Bonjour!',
    'greet' => 'Salut, %name% !',
], 'fr');

echo "en hello: ", $t->trans('hello'), "\n";
echo "fr hello: ", $t->trans('hello', [], null, 'fr'), "\n";
echo "en greet: ", $t->trans('greet', ['%name%' => 'World']), "\n";
echo "fr greet: ", $t->trans('greet', ['%name%' => 'Monde'], null, 'fr'), "\n";

// pluralized (legacy choice syntax)
echo "cart 0: ", $t->trans('cart.items', ['%count%' => 0]), "\n";
echo "cart 1: ", $t->trans('cart.items', ['%count%' => 1]), "\n";
echo "cart 5: ", $t->trans('cart.items', ['%count%' => 5]), "\n";

// fallback locale
$t->setFallbackLocales(['en']);
echo "missing in de falls to en: ", $t->trans('hello', [], null, 'de'), "\n";

// catalog metadata
$cat = $t->getCatalogue('en');
echo "en domains: ", implode(',', $cat->getDomains()), "\n";
echo "en has hello: ", $cat->has('hello') ? 'y' : 'n', "\n";
echo "en has missing: ", $cat->has('not-there') ? 'y' : 'n', "\n";
