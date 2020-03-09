#!/bin/bash
set -e

# GITHUB_TOKEN is a GitHub private access token configured for repo:status scope
# DROPBOX_TOKEN is an access token for the Dropbox API

CTEST_SKIP_RUN=${CTEST_SKIP_RUN:=false}
CTEST_SKIP_UPLOAD=${CTEST_SKIP_UPLOAD:=false}
CTEST_LOG=/tmp/ctest.log

if [ "$GITHUB_ACTIONS" = "true" ]; then
  REPO_NAME=$(basename "$GITHUB_REPOSITORY")
  REPO_FULL_NAME=$GITHUB_REPOSITORY
  if [ "$(echo "$GITHUB_REF" | cut -d '/' -f4)" = "merge" ]; then
    PULL_REQUEST=$(echo "$GITHUB_REF" | cut -d '/' -f3)
  fi
fi

status() {
  if [ "$SHIPPABLE" = "true" ] || [ "$GITHUB_ACTIONS" = "true" ]; then
    if [ "$PULL_REQUEST" != "" ]; then
      DESCRIPTION=$(echo "$2" | cut -b -100)
      DATA="{\"state\": \"$1\", \"description\": \"$DESCRIPTION\", \"context\": \"github / ctest\"}"
      PULL_REQUEST_STATUS=$(curl -s -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: $REPO_FULL_NAME" -X GET "https://api.github.com/repos/$REPO_FULL_NAME/pulls/$PULL_REQUEST")
      STATUSES_URL=$(echo "$PULL_REQUEST_STATUS" | jq -r '.statuses_url')
      curl -s -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: $REPO_FULL_NAME" -X POST -d "$DATA" "$STATUSES_URL" 1>/dev/null

      if [ "$1" = "failure" ]; then
        FAILED_TESTS=$(grep "[0-9] - " $CTEST_LOG | sed 's:\t  :<li>:g' | sed 's:(Failed):(Failed)</li>:g' | awk 1 ORS='')
        DATA="{\"body\": \"The following tests FAILED:<br><ul>$FAILED_TESTS</ul>\"}"
        curl -s -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: $REPO_FULL_NAME" -X POST -d "$DATA" "https://api.github.com/repos/$REPO_FULL_NAME/issues/$PULL_REQUEST/comments" 1>/dev/null
      fi
    fi

    if [ "$PULL_REQUEST" != "" -a "$1" != "pending" -a "$CTEST_SKIP_UPLOAD" != "true" ]; then
      BADGE_COLOR=red
      if [ "$FAILED" -eq 0 ]; then
        BADGE_COLOR=brightgreen
      fi

      BADGE_TEXT=$PASSED%20%2F%20$TESTS
      wget -O /tmp/ctest_"${REPO_NAME}"_"${BRANCH}".svg https://img.shields.io/badge/ctest-"$BADGE_TEXT"-"$BADGE_COLOR".svg 1>/dev/null
      curl -s -X POST "https://api-content.dropbox.com/2/files/upload" \
        -H "Authorization: Bearer $DROPBOX_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        -H "Dropbox-API-Arg: {\"path\": \"/ctest_${REPO_NAME}_${BRANCH}.svg\", \"mode\": \"overwrite\"}" \
        --data-binary @/tmp/ctest_"${REPO_NAME}"_"${BRANCH}".svg 1>/dev/null
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
