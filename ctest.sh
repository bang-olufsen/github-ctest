#!/bin/bash

# GITHUB_TOKEN is a GitHub private access token configured for repo:status scope
# DROPBOX_TOKEN is an access token for the Dropbox API
CTEST_SKIP_RUN=${CTEST_SKIP_RUN:=false}
CTEST_SKIP_UPLOAD=${CTEST_SKIP_UPLOAD:=false}
CTEST_CONTEXT_NAME=${CTEST_CONTEXT_NAME:=ctest}
CTEST_LOG=/tmp/${CTEST_CONTEXT_NAME}.log

status() {
  if [ "$SHIPPABLE" = "true" ]; then
    if [ "$IS_PULL_REQUEST" = "true" ]; then
      # Limit the description to 100 characters
      DESCRIPTION=$(echo "$2" | cut -b -100)
      DATA="{\"state\": \"$1\", \"target_url\": \"$BUILD_URL\", \"description\": \"$DESCRIPTION\", \"context\": \"$CTEST_CONTEXT_NAME\"}"
      GITHUB_API="https://api.github.com/repos/$REPO_FULL_NAME/statuses/$COMMIT"
      curl -s -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: bangolufsen/ctest" -X POST -d "$DATA" "$GITHUB_API" 1>/dev/null

      if [ "$1" = "failure" ]; then
        # GitHub does not allow tabs and regular line feeds for comments so use HTML instead
        FAILED_TESTS=$(grep "[0-9] - " $CTEST_LOG | sed 's:\t  :<li>:g' | sed 's:(Failed):(Failed)</li>:g' | awk 1 ORS='')
        DATA="{\"body\": \"The following tests FAILED:<br><ul>$FAILED_TESTS</ul>\"}"
        GITHUB_API="https://api.github.com/repos/$REPO_FULL_NAME/issues/$PULL_REQUEST/comments"
        curl -s -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: bangolufsen/ctest" -X POST -d "$DATA" "$GITHUB_API" 1>/dev/null
      fi
    fi

    if [ "$IS_PULL_REQUEST" != "true" -a "$1" != "pending" -a "$CTEST_SKIP_UPLOAD" != "true" ]; then
      BADGE_COLOR=red
      if [ "$FAILED" -eq 0 ]; then
        BADGE_COLOR=brightgreen
      fi

      if [ "x$BADGE_TEXT" = "x" ]; then
        BADGE_TEXT=$PASSED%20%2F%20$TESTS
      fi
      wget -O /tmp/"${CTEST_CONTEXT_NAME}"_"${REPO_NAME}"_"${BRANCH}".svg https://img.shields.io/badge/"${CTEST_CONTEXT_NAME}"-"$BADGE_TEXT"-"$BADGE_COLOR".svg 1>/dev/null
      curl -s -X POST "https://api-content.dropbox.com/2/files/upload" \
        -H "Authorization: Bearer $DROPBOX_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        -H "Dropbox-API-Arg: {\"path\": \"/${CTEST_CONTEXT_NAME}_${REPO_NAME}_${BRANCH}.svg\", \"mode\": \"overwrite\"}" \
        --data-binary @/tmp/"${CTEST_CONTEXT_NAME}"_"${REPO_NAME}"_"${BRANCH}".svg
    fi
  fi
}

plural() {
  if [ "$1" = "1" ]; then
    echo "$1 $2"
  else
    echo "$1 $2s"
  fi
}

if [ "$CTEST_SKIP_RUN" = "true" ]; then
  status "success" "Skipped"
  exit 0
fi

status "pending" "Running ctest with args $*"
ctest "$@" 2>&1 | tee "$CTEST_LOG"

# Check if we should do anything else than report the failing test cases
if [ "$(grep -c "No tests were found" $CTEST_LOG)" -gt 0 ]; then
  DESCRIPTION="No tests to be executed"
  TESTS=0
  FAILED=0
  PASSED=0
elif [ "$CTEST_CONTEXT_NAME" = "tsan" ]; then
  # If there are any ThreadSanitizer errors, report those instead of failing tests
  REPORTS=$(grep "ThreadSanitizer: reported" $CTEST_LOG)
  if [ "x$REPORTS" != "x" ]; then
    FAILED=$(echo "$REPORTS" | awk '{ print $3 }' | paste -sd+ | bc)
    BADGE_TEXT=$(plural "$FAILED" error)
    DESCRIPTION="ThreadSanitizer reported $BADGE_TEXT in $(echo "$REPORTS" | wc -l) tests"
  fi
elif [ "$CTEST_CONTEXT_NAME" = "asan" ]; then
  # If there are any AddressSanitizer errors (discounting leaks), report those instead of failing tests
  REPORTS=$(grep "ERROR: AddressSanitizer:" $CTEST_LOG)
  if [ "x$REPORTS" != "x" ]; then
    FAILED=$(echo "$REPORTS" | wc -l)
    BADGE_TEXT=$(plural "$FAILED" error)
    DESCRIPTION="ThreadSanitizer reported $BADGE_TEXT in $(grep -c "SUMMARY: AddressSanitizer:" $CTEST_LOG) tests"
  else
    # If leaks are the only kind of AddressSanitizer error, report those instead of failing tests
    REPORTS=$(grep "SUMMARY: AddressSanitizer:.*leaked in" $CTEST_LOG)
    if [ "x$REPORTS" != "x" ]; then
      FAILED=$(echo "$REPORTS" | awk '{ print $7 }' | paste -sd+ | bc)
      BADGE_TEXT=$(plural "$FAILED" leak)
      DESCRIPTION="AddressSanitizer reported $BADGE_TEXT in $(echo "$REPORTS" | wc -l) tests"
    fi
  fi
fi

# If we haven't anything else to report, report any failing tests
if [ "x$FAILED" = "x" ]; then
  DESCRIPTION=$(grep "tests passed" $CTEST_LOG | tail -n 1)
  TESTS=$(echo "$DESCRIPTION" | awk '{ print $NF }')
  FAILED=$(echo "$DESCRIPTION" | awk '{ print $4 }')
  PASSED=$((TESTS - FAILED))
fi

if [ "$FAILED" = "0" ]; then
  status "success" "$DESCRIPTION"
else
  status "failure" "$DESCRIPTION"
fi
