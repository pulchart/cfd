"""The fat95 package of the newest successful fat95 CI run, for run.py when
GH_TOKEN is set. The token needs read access to the Actions of pulchart/fat95;
artifacts cannot be downloaded without one, even from a public repository.
"""

import io
import json
import os
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

API = "https://api.github.com/repos/pulchart/fat95/actions"
DEST = Path(__file__).resolve().parent.parent.parent / "build/deps/fat95-ci"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a):
        return None


def request(url):
    return urllib.request.Request(
        url,
        headers={
            "Authorization": "Bearer " + os.environ["GH_TOKEN"],
            "Accept": "application/vnd.github+json",
        },
    )


def download(url):
    """The API redirects to storage, which must not get the token."""
    try:
        urllib.request.build_opener(NoRedirect).open(request(url))
    except urllib.error.HTTPError as e:
        if e.code == 302:
            return urllib.request.urlopen(e.headers["Location"]).read()
        raise
    raise OSError("no redirect to the artifact")


def latest():
    """build/deps/fat95-ci/fat95.lha and where it comes from, or None and why not."""
    try:
        url = API + "/workflows/ci.yml/runs?status=success&per_page=1"
        run = json.load(urllib.request.urlopen(request(url)))["workflow_runs"][0]
        arts = json.load(urllib.request.urlopen(request(run["artifacts_url"])))["artifacts"]
        art = next(x for x in arts if x["name"].startswith("fat95.v") and not x["expired"])
        with zipfile.ZipFile(io.BytesIO(download(art["archive_download_url"]))) as z:
            (name,) = [n for n in z.namelist() if n.endswith(".lha")]
            DEST.mkdir(parents=True, exist_ok=True)
            (DEST / "fat95.lha").write_bytes(z.read(name))
    except (OSError, LookupError, StopIteration, ValueError) as e:
        return None, "no fat95 CI package (%s)" % (e,)
    return DEST / "fat95.lha", "%s, fat95 CI run %d (%s)" % (name, run["id"], run["head_branch"])
