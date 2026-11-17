<?php
// extract's if-exists modes find no $this variable to overwrite
class Holder {
    public function run(int $flags): void {
        $data = ['this' => 'value', 'local' => 'new'];
        $local = 'old';
        try {
            echo extract($data, $flags, 'p'), ' ', get_class($this), ' ', $local, ' ', $p_this ?? 'unset', "\n";
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
    }
}
foreach ([EXTR_IF_EXISTS, EXTR_IF_EXISTS | EXTR_REFS, EXTR_PREFIX_IF_EXISTS, EXTR_PREFIX_IF_EXISTS | EXTR_REFS, EXTR_OVERWRITE, EXTR_SKIP, EXTR_PREFIX_SAME] as $flags) {
    (new Holder)->run($flags);
}
