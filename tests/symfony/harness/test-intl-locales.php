<?php
// exercises symfony/intl Locales/Countries/Languages helpers — these hit ICU
// resource bundles heavily (Locale, NumberFormatter, IntlDateFormatter, etc.)
require __DIR__ . '/../app/vendor/autoload.php';

use Symfony\Component\Intl\Locales;
use Symfony\Component\Intl\Countries;
use Symfony\Component\Intl\Languages;
use Symfony\Component\Intl\Currencies;

// Locales
echo "exists en_US: ", Locales::exists('en_US') ? 'y' : 'n', "\n";
echo "exists xx_YY: ", Locales::exists('xx_YY') ? 'y' : 'n', "\n";
echo "en_US name: ", Locales::getName('en_US', 'en'), "\n";
echo "de_DE in en: ", Locales::getName('de_DE', 'en'), "\n";
echo "de_DE in de: ", Locales::getName('de_DE', 'de'), "\n";

// Countries
echo "country US in en: ", Countries::getName('US', 'en'), "\n";
echo "country FR in en: ", Countries::getName('FR', 'en'), "\n";
echo "country JP in ja: ", Countries::getName('JP', 'ja'), "\n";
echo "country exists XX: ", Countries::exists('XX') ? 'y' : 'n', "\n";

// Languages
echo "lang en in en: ", Languages::getName('en', 'en'), "\n";
echo "lang de in fr: ", Languages::getName('de', 'fr'), "\n";
echo "lang exists xx: ", Languages::exists('xx') ? 'y' : 'n', "\n";

// Currencies
echo "ccy USD name en: ", Currencies::getName('USD', 'en'), "\n";
echo "ccy EUR name de: ", Currencies::getName('EUR', 'de'), "\n";
echo "ccy USD symbol en_US: ", Currencies::getSymbol('USD', 'en_US'), "\n";
echo "ccy EUR symbol fr: ", Currencies::getSymbol('EUR', 'fr'), "\n";
echo "ccy fraction USD: ", Currencies::getFractionDigits('USD'), "\n";
echo "ccy fraction JPY: ", Currencies::getFractionDigits('JPY'), "\n";

echo "done\n";
