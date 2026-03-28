<?php
// covers: relative qualified names in new expressions and static calls,
// use-alias resolution for qualified names

namespace App\Models;

class User {
    public $name;
    public function __construct($name) { $this->name = $name; }
}

namespace App\Services;

class UserService {
    public static function create($name) {
        return new \App\Models\User($name);
    }
}

namespace App;

// relative qualified name: Models\User resolves to App\Models\User
class Factory {
    public static function make() {
        return new Models\User("relative");
    }
}

$u1 = Factory::make();
echo $u1->name . "\n";

$u2 = Services\UserService::create("qualified_call");
echo $u2->name . "\n";

// use alias for first segment
namespace Test;

use App\Models as M;

class Builder {
    public static function build() {
        return new M\User("aliased");
    }
}

$u3 = Builder::build();
echo $u3->name . "\n";
echo get_class($u3) . "\n";

// static call with aliased namespace
use App\Services as S;

echo S\UserService::create("alias_call")->name . "\n";
