"""Record completed fake mutations, including an intentional failure."""
import json
import os
import sys
import time

time.sleep(0.12)
with open(os.environ["QUICKSHELL_TEST_ACTION_LOG"], "a") as output:
    output.write(json.dumps(sys.argv[1]) + "\n")
if sys.argv[1] == "fail":
    print("Intentional action failure", file=sys.stderr)
    raise SystemExit(1)
