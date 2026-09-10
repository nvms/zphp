<?php
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
switch ($path) {
    case '/health': echo "ok"; break;
    case '/counter': demo_counter(); echo demo_counter(); break;
    case '/hits': echo demo_hits(); break;
    case '/const': echo Demo\Counter::LIMIT, "|", Demo\Counter::NAME, "|", DEMO_VERSION, "|", DEMO_ANSWER; break;
    case '/ini': echo ini_get("demo.greeting"); ini_set("demo.greeting", "changed"); echo "|", demo_greet("x"); break;
    case '/leak': $GLOBALS['b'] = demo_open(4); demo_write($GLOBALS['b'], "ab"); echo "made"; break;
    case '/freed': echo demo_freed(); break;
    case '/obj': $c = new Demo\Counter(1); echo $c->increment()->value(), "|", demo_describe($c); break;
    case '/throw': try { demo_throw("x"); } catch (DemoException $e) { echo "caught ", $e->getMessage(); } break;
    default: http_response_code(404); echo "nf";
}
