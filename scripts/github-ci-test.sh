#!/bin/bash
# Run tests

set -eux
set -o pipefail

export IS_CI=1

mkdir -p artifacts
mkdir -p build/reports

set +e
./scripts/build.sh test -d -s Release -x "Hammerspoon/Build Configs/Hammerspoon-Test.xcconfig"
XCODE_TEST_STATUS=$?
set -e

mv build/test.log artifacts

#BUILD_ROOT="$(xcodebuild -workspace Hammerspoon.xcworkspace -scheme Release -showBuildSettings | sort | uniq | grep " BUILD_ROOT =" | awk '{ print $3 }')"
#trainer --fail_build false -p "${BUILD_ROOT}/../../Logs/Test/" -o build/reports/

trainer --fail_build false -p "build/" -o build/reports/

echo "Produced test reports:"
ls build/reports/*.xml

# FIXME: Can we do this a bit more gracefully?
mv build/reports/*.xml build/reports/junit.xml

RESULT=$(grep -A1 "Test Suite 'All tests'" artifacts/test.log | tail -1 | sed -e 's/^[ ]+//')

echo "::set-output name=test_result::${RESULT}"

if [ "${XCODE_TEST_STATUS}" -eq 0 ] && [[ "${RESULT}" == *"0 failures"* ]]; then
    echo "::set-output name=test_result_short::Passed"
    exit 0
else
    echo "::set-output name=test_result_short::Failed"
    exit 1
fi
