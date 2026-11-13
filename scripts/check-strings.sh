#!/bin/bash
# Check that the String Catalog and the L("…") calls in LidAwake.swift agree.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift scripts/check-strings.swift
