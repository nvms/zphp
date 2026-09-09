<?php
// covers: native string results that share an argument, copy a literal,
// transfer a fresh buffer, or forward a VM call result; results stored into
// arrays and objects; direct native-to-native calls; __toString coercion;
// PDO column values surviving statement teardown; file reads with offsets

namespace Own\Deep {
    /** the documented class */
    class Doc
    {
        /** the documented method */
        public function m(): string
        {
            return "m";
        }
    }
}

namespace {
    function show($label, $v)
    {
        echo $label, ": ", var_export($v, true), "\n";
    }

    $s = "Hello, World";
    show("substr-share", substr($s, 0));
    show("substr-slice", substr($s, 7));
    show("substr-copy", substr(strtoupper($s), 0, 5));
    show("repeat-1", str_repeat($s, 1));
    show("trim-noop", trim($s));
    show("ucfirst-noop", ucfirst($s));
    show("replace-nomatch", str_replace("zzz", "y", $s));
    show("replace-match", str_replace("World", "PHP", $s));
    show("shuffle-1", str_shuffle("a"));
    show("implode", implode("-", explode(", ", $s)));
    show("sprintf", sprintf("%s|%05d|%.2f", $s, 42, 3.14159));
    show("lower-noop", strtolower("already"));

    show("preg-nomatch", preg_replace('/zzz/', 'y', $s));
    show("preg-match", preg_replace('/o/', '0', $s));
    show("preg-array-subject", preg_replace('/l/', 'L', ["hello", "world", 7]));
    show("preg-array-pattern", preg_replace(['/a/', '/b/'], ['1', '2'], "abcab"));
    show("preg-limit", preg_replace('/a/', 'X', "banana", 2, $count));
    show("preg-count", $count);
    show("preg-callback", preg_replace_callback('/\d+/', fn($m) => $m[0] * 2, "a1b22c333"));
    show("preg-callback-array", preg_replace_callback_array(['/a/' => fn($m) => 'A', '/b/' => fn($m) => 'B'], "aabb"));
    show("preg-filter", preg_filter('/^a/', 'X', ["apple", "berry", "avocado"]));
    show("preg-filter-scalar-nomatch", preg_filter('/^z/', 'X', "apple"));
    show("preg-split", preg_split('/[\s,]+/', "a, b  c,d"));
    show("preg-quote", preg_quote("a.b*c"));
    show("preg-last-error-msg", preg_last_error_msg());

    $arr = ["x" => 1, "y" => 2, 10 => 3];
    show("array-search-key", array_search(2, $arr));
    show("array-key-first", array_key_first($arr));
    show("array-key-last", array_key_last($arr));
    show("array-keys", array_keys($arr));
    show("array-flip", array_flip(["a" => "b", "c" => "d"]));

    $stored = [];
    for ($i = 0; $i < 50; $i++) {
        $stored[] = substr("prefix-" . $i, 7);
        $stored[] = str_pad((string) $i, 3, "0", STR_PAD_LEFT);
    }
    show("stored-count", count($stored));
    show("stored-tail", array_slice($stored, -4));

    $obj = new stdClass();
    $obj->name = strtoupper("counted");
    $obj->copy = substr($obj->name, 0);
    $obj->name = trim(" replaced ");
    show("object-props", [$obj->name, $obj->copy]);

    show("eval-string", eval('return "ev" . "al";'));
    show("eval-int", eval('return 40 + 2;'));
    show("eval-array", eval('return ["k" => strrev("abc")];'));

    class Stringy
    {
        public function __toString(): string
        {
            return "stringy-" . str_repeat("x", 3);
        }
    }
    $st = new Stringy();
    show("tostring-concat", "<" . $st . ">");
    show("tostring-strlen", strlen($st));
    show("tostring-pad", str_pad($st, 12, "."));
    show("tostring-in-array", in_array("stringy-xxx", [$st]));
    show("tostring-strval", strval($st));

    class Holder
    {
        public $v = 1;
    }
    $closure = function () {
        return $this->v;
    };
    $h = new Holder();
    $h->v = 7;
    $bound = Closure::bind($closure, $h, Holder::class);
    show("closure-bind", $bound());
    $bound2 = $closure->bindTo($h);
    show("closure-bindto", $bound2());
    show("closure-call", $closure->call($h));
    $fc = Closure::fromCallable('strtoupper');
    show("closure-from-callable", $fc("abc"));

    $rc = new ReflectionClass(\Own\Deep\Doc::class);
    show("refl-short", $rc->getShortName());
    show("refl-ns", $rc->getNamespaceName());
    show("refl-doc", $rc->getDocComment());
    show("refl-file", basename($rc->getFileName()));
    $rm = $rc->getMethod("m");
    show("refl-method-doc", $rm->getDocComment());
    show("refl-method-file", basename($rm->getFileName()));
    $rf = new ReflectionFunction('show');
    show("refl-fn-short", $rf->getShortName());
    show("refl-fn-ns", $rf->getNamespaceName());
    $rp = new ReflectionProperty(Holder::class, "v");
    show("refl-prop-value", $rp->getValue($h));
    show("refl-prop-has-type", $rp->hasType());
    show("refl-invoke", $rm->invoke(new \Own\Deep\Doc()));
    show("refl-invoke-args", $rm->invokeArgs(new \Own\Deep\Doc(), []));

    $pdo = new PDO("sqlite::memory:");
    $pdo->exec("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, grp TEXT, price REAL)");
    $ins = $pdo->prepare("INSERT INTO t (name, grp, price) VALUES (?, ?, ?)");
    foreach ([["apple", "fruit", 1.5], ["pear", "fruit", 2.25], ["kale", "veg", 0.75], ["", "veg", 0]] as $row) {
        $ins->execute($row);
    }
    $rows = [];
    $st = $pdo->query("SELECT id, name, grp FROM t ORDER BY id");
    $rows["assoc"] = $st->fetchAll(PDO::FETCH_ASSOC);
    $st = $pdo->query("SELECT id, name FROM t ORDER BY id");
    $rows["num"] = $st->fetchAll(PDO::FETCH_NUM);
    $st = $pdo->query("SELECT id, name FROM t ORDER BY id");
    $rows["both"] = $st->fetch(PDO::FETCH_BOTH);
    $st = $pdo->query("SELECT name FROM t ORDER BY id");
    $rows["column"] = $st->fetchAll(PDO::FETCH_COLUMN);
    $st = $pdo->query("SELECT name, price FROM t ORDER BY id");
    $rows["keypair"] = $st->fetchAll(PDO::FETCH_KEY_PAIR);
    $st = $pdo->query("SELECT grp, name, price FROM t ORDER BY id");
    $rows["group"] = $st->fetchAll(PDO::FETCH_GROUP | PDO::FETCH_ASSOC);
    $st = $pdo->query("SELECT grp, name FROM t ORDER BY id");
    $rows["unique"] = $st->fetchAll(PDO::FETCH_UNIQUE | PDO::FETCH_ASSOC);
    $st = $pdo->query("SELECT name, price FROM t ORDER BY id");
    $rows["func"] = $st->fetchAll(PDO::FETCH_FUNC, fn($n, $p) => $n . "=" . $p);
    $st = $pdo->query("SELECT name, grp FROM t ORDER BY id");
    $rows["obj"] = $st->fetch(PDO::FETCH_OBJ);
    $st = $pdo->query("SELECT name, grp FROM t ORDER BY id");
    $rows["named"] = $st->fetch(PDO::FETCH_NAMED);
    $st = $pdo->query("SELECT name FROM t WHERE id = 2");
    $rows["fetchcolumn"] = $st->fetchColumn();
    $st = $pdo->query("SELECT name FROM t WHERE id = 4");
    $rows["fetchcolumn-empty"] = $st->fetchColumn();
    class Row
    {
        public $name;
        public $grp;
    }
    $st = $pdo->query("SELECT name, grp FROM t ORDER BY id");
    $st->setFetchMode(PDO::FETCH_CLASS, Row::class);
    $rows["class"] = $st->fetch();
    $st = null;
    $pdo = null;
    show("pdo-rows", $rows);
    show("pdo-driver", "sqlite");

    $tmp = tempnam(sys_get_temp_dir(), "own");
    file_put_contents($tmp, "0123456789\nline two\nline three\n");
    show("fgc-all", file_get_contents($tmp));
    show("fgc-offset", file_get_contents($tmp, false, null, 4));
    show("fgc-offset-length", file_get_contents($tmp, false, null, 2, 5));
    show("fgc-negative-offset", file_get_contents($tmp, false, null, -6));
    show("file-lines", file($tmp, FILE_IGNORE_NEW_LINES));
    show("filetype", filetype($tmp));
    show("readlink-basename", basename(realpath($tmp)) === basename($tmp));
    show("pathinfo-ext", pathinfo("/a/b/c.tar.gz", PATHINFO_EXTENSION));
    show("pathinfo-file", pathinfo("/a/b/c.tar.gz", PATHINFO_FILENAME));
    show("pathinfo-dir", pathinfo("/a/b/c.tar.gz", PATHINFO_DIRNAME));
    show("pathinfo-base", pathinfo("/a/b/c.tar.gz", PATHINFO_BASENAME));
    $gz = $tmp . ".gz";
    file_put_contents($gz, gzencode("alpha\nbeta\ngamma"));
    show("gzfile", gzfile($gz));
    show("gz-roundtrip", gzdecode(file_get_contents($gz)));
    $fh = fopen($tmp, "r");
    show("fgets", fgets($fh));
    show("fread", fread($fh, 4));
    fclose($fh);
    $tf = tmpfile();
    fwrite($tf, "temp data");
    rewind($tf);
    show("tmpfile", fread($tf, 100));
    fclose($tf);
    unlink($gz);
    unlink($tmp);
    show("stream-resolve", stream_resolve_include_path("/definitely/missing/path"));
    show("sys-temp-dir-string", is_string(sys_get_temp_dir()));
    show("uname-mode", in_array(php_uname("s"), ["Darwin", "Linux"], true));

    $json = json_encode(["k" => ["nested" => "v", "n" => [1, 2, 3]], "s" => "str"]);
    show("json", $json);
    $decoded = json_decode($json, true);
    $decoded["k"]["nested"] = strtoupper($decoded["k"]["nested"]);
    show("json-decoded", $decoded);
    $ser = serialize(["a" => "b", "o" => $h]);
    show("serialize", $ser);
    show("unserialize", unserialize($ser));
    show("var-export-nul", var_export("a\0b", true));

    $doc = new DOMDocument();
    $doc->loadXML('<root a="1"><child>text</child><child>more</child></root>');
    $root = $doc->documentElement;
    show("dom-node-name", $root->nodeName);
    show("dom-attr", $root->getAttribute("a"));
    show("dom-first-child", $root->firstChild->textContent);
    show("dom-item", $doc->getElementsByTagName("child")->item(1)->nodeValue);
    show("dom-save", trim($doc->saveXML($root)));

    $sx = simplexml_load_string('<r><i n="1">one</i><i n="2">two</i></r>');
    show("sxml-string", (string) $sx->i[1]);
    show("sxml-attr", (string) $sx->i[0]["n"]);
    show("sxml-asxml", trim($sx->asXML()));

    $w = new XMLWriter();
    $w->openMemory();
    $w->startElement("e");
    $w->writeAttribute("k", "v");
    $w->text("body");
    $w->endElement();
    show("xmlwriter", $w->outputMemory());
    show("xmlwriter-flush-after", $w->outputMemory());

    show("sodium-hex", sodium_bin2hex("\x01\xab"));
    show("sodium-hash", sodium_bin2hex(sodium_crypto_generichash("abc", "", 16)));
    show("hash", hash("sha256", "abc"));
    show("md5", md5("abc"));
    show("base64", base64_encode("abc"));
    show("preg-scalar-subject", preg_replace('/l/', 'L', 7));
    show("preg-callback-scalar-subject", preg_replace_callback('/7/', fn($m) => "x", 7));
    show("preg-callback-array-scalar-subject", preg_replace_callback_array(['/7/' => fn($m) => "y"], 7));

    date_default_timezone_set("UTC");
    show("tz-get", date_default_timezone_get());
    $dt = new DateTime("2024-02-29 12:34:56", new DateTimeZone("UTC"));
    show("date-format", $dt->format("Y-m-d H:i:s T"));
    show("tz-name", $dt->getTimezone()->getName());
    show("date-fn", date("D, d M Y", 86400 * 365));
    show("strtotime", strtotime("2024-01-01 00:00:00 UTC"));
    show("date-parse", date_parse("2024-02-29 12:34:56")["year"]);

    $ini = parse_ini_string("a=1\nb=two\n[sec]\nc=3", true);
    show("ini", $ini);
    show("version-compare", version_compare("8.4.0", "8.5.0"));
    show("uniqid-len", strlen(uniqid()) >= 13);
    show("escapeshellarg", escapeshellarg("it's"));
    show("shell-exec", trim(shell_exec("echo shell-ok")));

    $it = new ArrayIterator(["p" => "q", "r" => "s"]);
    $out = [];
    foreach (new RegexIterator($it, '/^[qs]$/') as $k => $v) {
        $out[$k] = strtoupper($v);
    }
    show("regex-iterator", $out);
    $heap = new SplPriorityQueue();
    $heap->insert("low", 1);
    $heap->insert("high", 9);
    show("pq-extract", $heap->extract());
    $heap->next();
    show("pq-valid", $heap->valid());
    show("mb-convert", mb_convert_encoding("caf\xc3\xa9", "ISO-8859-1", "UTF-8") === "caf\xe9");
    show("filter-var", filter_var("42", FILTER_VALIDATE_INT));
    show("filter-var-array", filter_var_array(["n" => "7", "e" => "a@b.c"], ["n" => FILTER_VALIDATE_INT, "e" => FILTER_VALIDATE_EMAIL]));
    show("done", true);
}
