<?php
// ReflectionExtension's string form (php's _extension_string): the module
// heading, dependencies, ini entries with who may change them and the value
// before ini_set(), constants, functions and classes

function entry(string $text, string $name): string
{
    $at = strpos($text, "Entry [ $name ");
    if ($at === false) {
        return "no entry $name\n";
    }
    $end = strpos($text, "    }\n", $at);
    return substr($text, $at, $end + 6 - $at);
}

// a module's number depends on which extensions the php build loads
function shown(string $name): string
{
    return preg_replace('/extension #\d+ /', 'extension #N ', (string) new ReflectionExtension($name));
}

echo shown('json');
echo shown('ctype');

ini_set('arg_separator.output', "f\0oo");
ini_set('precision', '10');
$core = (string) new ReflectionExtension('core');
echo preg_replace('/#\d+ /', '#N ', strtok($core, "\n")), "\n";
echo entry($core, 'arg_separator.output');
echo entry($core, 'precision');
echo entry($core, 'allow_url_fopen');
echo entry($core, 'max_input_time');
var_dump(ini_get_all('core')['precision']['access'], ini_get_all('core')['allow_url_fopen']['access']);

$pcre = (string) new ReflectionExtension('pcre');
echo entry($pcre, 'pcre.backtrack_limit');
echo entry($pcre, 'pcre.jit');

$standard = new ReflectionExtension('standard');
echo preg_replace('/#\d+ /', '#N ', strtok((string) $standard, "\n")), "\n";
echo $standard->getVersion(), "\n";
echo (new ReflectionExtension('dom'))->getVersion(), "\n";
