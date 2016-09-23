#!/bin/bash
set -e

# GITHUB_TOKEN is a GitHub private access token configured for repo:status scope
# DROPBOX_TOKEN is an access token for the Dropbox API

status () {
  if [ "$SHIPPABLE" = "true" ]; then
    if [ "$IS_PULL_REQUEST" = "true" ]; then
      # Limit the description to 100 characters even though GitHub supports up to 140 characters
      DESCRIPTION=`echo $2 | cut -b -100`
      DATA="{ \"state\": \"$1\", \"target_url\": \"$BUILD_URL\", \"description\": \"$DESCRIPTION\", \"context\": \"ctest\"}"
      GITHUB_API="https://api.github.com/repos/$REPO_FULL_NAME/statuses/$COMMIT"
      curl -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: bangolufsen/ctest" -X POST -d "$DATA" $GITHUB_API 1>/dev/null 2>&1
    fi

    if [ "$IS_PULL_REQUEST" != "true" -a "$1" != "pending" -a "$CTEST_SKIP_BADGE_UPLOAD" != "true" ]; then
      BADGE_COLOR=red
      if [ $FAILED -eq 0 ]; then
        BADGE_COLOR=brightgreen
      fi

      BADGE_TEXT=$PASSED%20%2F%20$TESTS
      wget -O /tmp/ctest_${REPO_NAME}_${BRANCH}.svg https://img.shields.io/badge/ctest-$BADGE_TEXT-$BADGE_COLOR.svg 1>/dev/null 2>&1
      curl -H "Authorization: Bearer $DROPBOX_TOKEN" https://api-content.dropbox.com/1/files_put/auto/ -T /tmp/ctest_${REPO_NAME}_${BRANCH}.svg 1>/dev/null 2>&1
    fi
  fi
}

status "pending" "Running ctest with args $*"
ctest $* 2>&1 | tee /tmp/ctest.log

DESCRIPTION=`cat /tmp/ctest.log | grep "tests passed"`
TESTS=`echo $DESCRIPTION | awk '{ print $NF }'`
FAILED=`echo $DESCRIPTION | awk '{ print $4 }'`
PASSED=`expr $TESTS - $FAILED`

if [ $FAILED -eq 0 ]; then
  status "success" "$DESCRIPTION"
else
  status "failure" "$DESCRIPTION"
fi
