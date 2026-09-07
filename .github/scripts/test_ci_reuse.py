import importlib.util
import io
import json
import unittest
import zipfile
from unittest.mock import patch
from pathlib import Path

spec = importlib.util.spec_from_file_location('ci_reuse', Path(__file__).with_name('ci_reuse.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReuseTests(unittest.TestCase):
    def check(self, tree='same', merged=True, expired=False, proof_head='head'):
        responses = [
            {'tree': {'sha': 'same'}},
            [{'merged_at': 'today' if merged else None, 'merge_commit_sha': 'merge',
              'number': 36, 'head': {'sha': 'head'}}],
            {'workflow_runs': [{'id': 10}]},
            {'artifacts': [{'id': 20, 'name': 'tested-source', 'expired': expired}]},
        ]
        data = io.BytesIO()
        with zipfile.ZipFile(data, 'w') as archive:
            archive.writestr('tested-source.json', json.dumps(
                {'tree': tree, 'head': proof_head, 'pull': 36, 'run': 10}))
        with patch.object(module, 'api', side_effect=responses), patch.object(
                module.subprocess, 'check_output', return_value=data.getvalue()):
            return module.reusable('owner/repo', 'merge')

    def test_identical_successful_tree(self):
        self.assertTrue(self.check())

    def test_changed_merge_tree(self):
        self.assertFalse(self.check(tree='different'))

    def test_unmerged_pull(self):
        self.assertFalse(self.check(merged=False))

    def test_expired_proof(self):
        self.assertFalse(self.check(expired=True))

    def test_wrong_head(self):
        self.assertFalse(self.check(proof_head='old'))

    def test_direct_push(self):
        with patch.object(module, 'api', side_effect=[{'tree': {'sha': 'same'}}, []]):
            self.assertFalse(module.reusable('owner/repo', 'direct'))


if __name__ == '__main__':
    unittest.main()
