#!/bin/bash

# GITHUB_TOKEN is a GitHub private access token configured for repo:status scope
# DROPBOX_TOKEN is an access token for the Dropbox API
CTEST_SKIP_RUN=${CTEST_SKIP_RUN:=false}
CTEST_SKIP_UPLOAD=${CTEST_SKIP_UPLOAD:=false}

status () {
  if [ "$SHIPPABLE" = "true" ]; then
    if [ "$IS_PULL_REQUEST" = "true" ]; then
      # Limit the description to 100 characters even though GitHub supports up to 140 characters
      DESCRIPTION=`echo $2 | cut -b -100`
      DATA="{ \"state\": \"$1\", \"target_url\": \"$BUILD_URL\", \"description\": \"$DESCRIPTION\", \"context\": \"ctest\"}"
      GITHUB_API="https://api.github.com/repos/$REPO_FULL_NAME/statuses/$COMMIT"
      curl -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: bangolufsen/ctest" -X POST -d "$DATA" $GITHUB_API 1>/dev/null 2>&1
    fi

    if [ "$IS_PULL_REQUEST" != "true" -a "$1" != "pending" -a "$CTEST_SKIP_UPLOAD" != "true" ]; then
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

if [ "$CTEST_SKIP_RUN" = "true" ]; then
  status "success" "Skipped"
  exit 0
fi

status "pending" "Running ctest with args $*"

LOG=/tmp/ctest.log
ctest $* 2>&1 | tee $LOG
DESCRIPTION=`cat $LOG | grep "tests passed"`

# With the ctest --verbose option we can count all the test cases
if [ `cat $LOG | grep "No tests were found" | wc -l` -gt 0 ]; then
  TESTS=0
  FAILED=0
  DESCRIPTION="No tests to be executed"
elif [ `cat $LOG | grep " Failures " | grep " Ignored" | wc -l` -gt 0 ]; then
  # Unity unit test parsing
  TESTS=`cat $LOG | grep " Ignored" | awk '{ print $2 }' | gawk 'BEGIN { sum = 0 } // { sum = sum + $0 } END { print sum }'`
  FAILED=`cat $LOG | grep " Ignored" | awk '{ print $4 }' | gawk 'BEGIN { sum = 0 } // { sum = sum + $0 } END { print sum }'`
elif [ `cat $LOG | grep ": Running" | wc -l` -gt 0 ]; then
  # Boost unit tests parsing
  TESTS=`cat $LOG | grep ": Running" | awk '{ print $3 }' | gawk 'BEGIN { sum = 0 } // { sum = sum + $0 } END { print sum }'`
  FAILED=`cat $LOG | grep ": \*" | awk '{ print $3 }' | gawk 'BEGIN { sum = 0 } // { sum = sum + $0 } END { print sum }'`
else
  # CTest parsing
  TESTS=`echo $DESCRIPTION | awk '{ print $NF }'`
  FAILED=`echo $DESCRIPTION | awk '{ print $4 }'`
fi

PASSED=`expr $TESTS - $FAILED`

if [ $FAILED -eq 0 ]; then
  status "success" "$DESCRIPTION"
else
  status "failure" "$DESCRIPTION"
fi
