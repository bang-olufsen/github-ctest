#!/bin/bash

# GITHUB_TOKEN is a GitHub private access token configured for repo:status scope
# DROPBOX_TOKEN is an access token for the Dropbox API
CTEST_SKIP_RUN=${CTEST_SKIP_RUN:=false}
CTEST_SKIP_UPLOAD=${CTEST_SKIP_UPLOAD:=false}
CTEST_LOG=/tmp/ctest.log

status() {
  if [ "$SHIPPABLE" = "true" ]; then
    if [ "$IS_PULL_REQUEST" = "true" ]; then
      # Limit the description to 100 characters
      DESCRIPTION=$(echo "$2" | cut -b -100)
      DATA="{\"state\": \"$1\", \"target_url\": \"$BUILD_URL\", \"description\": \"$DESCRIPTION\", \"context\": \"ctest\"}"
      GITHUB_API="https://api.github.com/repos/$REPO_FULL_NAME/statuses/$COMMIT"
      curl -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: bangolufsen/ctest" -X POST -d "$DATA" "$GITHUB_API"

      if [ "$1" = "failure" ]; then
        # GitHub does not allow tabs and regular line feeds for comments so use HTML instead
        FAILED_TESTS=$(grep "(Failed)" $CTEST_LOG | sed 's:\t  :<li>:g' | sed 's:(Failed):(Failed)</li>:g' | awk 1 ORS="<br>")
        DATA="{\"body\": \"The following tests FAILED:<br>$FAILED_TESTS\"}"
        GITHUB_API="https://api.github.com/repos/$REPO_FULL_NAME/issues/$PULL_REQUEST/comments"
        curl -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: bangolufsen/ctest" -X POST -d "$DATA" "$GITHUB_API"
      fi
    fi

    if [ "$IS_PULL_REQUEST" != "true" -a "$1" != "pending" -a "$CTEST_SKIP_UPLOAD" != "true" ]; then
      BADGE_COLOR=red
      if [ "$FAILED" -eq 0 ]; then
        BADGE_COLOR=brightgreen
      fi

      BADGE_TEXT=$PASSED%20%2F%20$TESTS
      wget -O /tmp/ctest_"${REPO_NAME}"_"${BRANCH}".svg https://img.shields.io/badge/ctest-"$BADGE_TEXT"-"$BADGE_COLOR".svg
      curl -X POST "https://api-content.dropbox.com/2/files/upload" \
        -H "Authorization: Bearer $DROPBOX_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        -H "Dropbox-API-Arg: {\"path\": \"/ctest_${REPO_NAME}_${BRANCH}.svg\", \"mode\": \"overwrite\"}" \
        --data-binary @/tmp/ctest_"${REPO_NAME}"_"${BRANCH}".svg
    fi
  fi
}

if [ "$CTEST_SKIP_RUN" = "true" ]; then
  status "success" "Skipped"
  exit 0
fi

status "pending" "Running ctest with args $*"
ctest "$@" 2>&1 | tee "$CTEST_LOG"

if [ "$(grep -c "No tests were found" $CTEST_LOG)" -gt 0 ]; then
  DESCRIPTION="No tests to be executed"
  TESTS=0
  FAILED=0
  PASSED=0
else
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
