#!/usr/bin/env bash
# Prints the UDID of the pinned simulator ($SIMULATOR_NAME on $SIMULATOR_RUNTIME), creating it when
# the runner has the runtime but not the device. Fails when the runtime is missing.
#
# Used by the ios and performance jobs in ci.yml. Snapshot references are recorded on exactly this
# simulator, so both jobs must pick the same one.
set -euo pipefail
: "${SIMULATOR_NAME:?}" "${SIMULATOR_RUNTIME:?}"

device="$(xcrun simctl list devices available -j | SIM_NAME="$SIMULATOR_NAME" SIM_RUNTIME="$SIMULATOR_RUNTIME" python3 -c 'import json,os,sys; d=json.load(sys.stdin)["devices"]; ids=[x["udid"] for k in d if k.startswith(os.environ["SIM_RUNTIME"]) for x in d[k] if x["name"] == os.environ["SIM_NAME"]]; print(ids[0] if ids else "")')"
if [ -z "$device" ]; then
  runtime="$(xcrun simctl list runtimes available -j | SIM_RUNTIME="$SIMULATOR_RUNTIME" python3 -c 'import json,os,sys; r=[x["identifier"] for x in json.load(sys.stdin)["runtimes"] if x["identifier"].startswith(os.environ["SIM_RUNTIME"])]; print(sorted(r)[-1] if r else "")')"
  if [ -z "$runtime" ]; then echo "::error::no simulator runtime $SIMULATOR_RUNTIME* on this runner" >&2; exit 1; fi
  device="$(xcrun simctl create "$SIMULATOR_NAME" "$SIMULATOR_NAME" "$runtime")"
  echo "created $SIMULATOR_NAME on $runtime" >&2
fi
echo "$device"
