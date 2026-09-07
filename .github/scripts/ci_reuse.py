import io
import json
import os
import subprocess
import zipfile


def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', path]))


def reusable(repo, sha):
    commit = api(f'repos/{repo}/git/commits/{sha}')
    pulls = api(f'repos/{repo}/commits/{sha}/pulls')
    for pull in pulls:
        if not pull['merged_at'] or pull['merge_commit_sha'] != sha:
            continue
        head = pull['head']['sha']
        runs = api(f'repos/{repo}/actions/workflows/ci.yml/runs?event=pull_request&head_sha={head}&status=success&per_page=100')['workflow_runs']
        for run in runs:
            artifacts = api(f'repos/{repo}/actions/runs/{run["id"]}/artifacts')['artifacts']
            for artifact in artifacts:
                if artifact['name'] != 'tested-source' or artifact['expired']:
                    continue
                data = subprocess.check_output(['gh', 'api', f'repos/{repo}/actions/artifacts/{artifact["id"]}/zip'])
                with zipfile.ZipFile(io.BytesIO(data)) as archive:
                    proof = json.loads(archive.read('tested-source.json'))
                if (proof['tree'] == commit['tree']['sha']
                        and proof['head'] == head
                        and proof['pull'] == pull['number']
                        and proof['run'] == run['id']):
                    return True
    return False


def main():
    repo = os.environ['GITHUB_REPOSITORY']
    sha = os.environ['GITHUB_SHA']
    event = json.load(open(os.environ['GITHUB_EVENT_PATH']))
    if os.environ['GITHUB_EVENT_NAME'] == 'pull_request':
        tree = subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], text=True).strip()
        proof = {'tree': tree, 'head': event['pull_request']['head']['sha'],
                 'pull': event['number'], 'run': int(os.environ['GITHUB_RUN_ID'])}
        with open('tested-source.json', 'w') as output:
            json.dump(proof, output)
        skip = False
    else:
        try:
            skip = reusable(repo, sha)
        except Exception as error:
            print(f'Cannot verify prior CI; running full suite: {error}')
            skip = False
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'run-tests={str(not skip).lower()}\n')
    print('Identical source already passed PR CI' if skip else 'Running full CI')


if __name__ == '__main__':
    main()
