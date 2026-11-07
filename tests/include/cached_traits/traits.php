<?php
trait CachedGuarded { protected function guarded() { return 'guarded'; } }
trait CachedSealed { final public function sealed() { return 'sealed'; } }
