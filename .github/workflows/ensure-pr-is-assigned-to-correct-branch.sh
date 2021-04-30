#!/usr/bin/env bash

PR_NUMBER=$(jq -r ".pull_request.number" "$GITHUB_EVENT_PATH")
if [[ "$PR_NUMBER" == "null" ]]; then
    PR_NUMBER=$(jq -r ".issue.number" "$GITHUB_EVENT_PATH")
fi
if [[ "$PR_NUMBER" == "null" ]]; then
    echo "Failed to determine PR Number."
    exit 1
fi
echo "Collecting information about PR #$PR_NUMBER of $GITHUB_REPOSITORY..."

pr_resp=$(curl -X GET -s -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER")

# Source branch
HEAD_BRANCH=$(echo "$pr_resp" | jq -r .head.ref)

# Destination branch
BASE_BRANCH=$(echo "$pr_resp" | jq -r .base.ref)

# Destination branch
PR_TITLE=$(echo "$pr_resp" | jq -r .title)

comment() {
    curl -s -o /dev/null -X POST -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{\"body\": \"$1\"}" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments
}

switch_base() {
    NEW_BASE="$1"
    curl -s \
        -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" \
        -d "{\"base\": \"$NEW_BASE\"}"
}

reject_pr() {
    comment "$@"
    NEW_TITLE=$(echo "$PR_TITLE" | sed 's/^\[REJECTED\]\s*//')
    curl -s \
        -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" \
        -d "{\"title\":\"[REJECTED] $NEW_TITLE\", \"state\": \"closed\"}"
}

# Ensure release and hotfix are merged to
if [[ "$HEAD_BRANCH" =~ ^(release|hotfix)\/ ]]; then
    echo "Ensure merge to main"
    if [[ "$BASE_BRANCH" != "main" ]]; then
        echo "::warning ::Trying to merge to wrong branch, $BASE_BRANCH, switching to main"
        comment "Wrong branch selected, switching to \`main\`"
        switch_base "main"
    fi
    exit 0
fi

# Ensure feature and bug are merged to develop
if [[ "$HEAD_BRANCH" =~ ^(feature|bug)\/ ]]; then
    echo "Ensure merge to develop"
    if [[ "$BASE_BRANCH" != "develop" ]]; then
        echo "::warning ::Trying to merge to wrong branch, $BASE_BRANCH, switching to develop"
        comment "Wrong branch selected, switching to \`develop\`"
        switch_base "develop"
    fi
    exit 0
fi

if [[ "$BASE_BRANCH" == "main" ]]; then
    echo "::error ::Direct merging to main is only permitted from release or hotfix, closing PR"
    reject_pr "Direct merge from \`$HEAD_BRANCH\` to \`main\` is not permitted! Create a \`release/\` or \`hotfix/\` branch first!"
fi

if [[ "$BASE_BRANCH" == "develop" ]]; then
    echo "::error ::Direct merging to develop is only permitted from feature or bug, closing PR"
    reject_pr "Direct merge from \`$HEAD_BRANCH\` to \`develop\` is not permitted! Create a \`feature/\` or \`bug/\` branch first!"
fi
