#!/usr/bin/env bash
# cleanup.sh - turns a fresh al-folio fork into a clean personal blog.
# Run from the repo root:   bash cleanup.sh            (asks before changing anything)
#
# Flags:  --dry-run      show what would happen, change nothing
#         --yes          don't ask for confirmation
#         --no-build     skip the local jekyll build checks
#         --no-ruby      don't try to install ruby/bundler with pacman
#         --only-config  only edit _config.yml (CFG=path to override the file)
#
# Safety: it tags the current commit as "pre-cleanup" first, makes NO commits
# (review with git status, then commit yourself), and stops if a build check fails. Undo everything with:
#         git reset --hard pre-cleanup

set -u
DRY=0
YES=0
BUILD=1
RUBY=1
ONLY_CFG=0
BLOG_NAME="${BLOG_NAME:-clswhre}"
BLOG_DESC="${BLOG_DESC:-Cybersecurity student learning log: labs, CTF writeups, notes.}"
CFG="${CFG:-_config.yml}"
for a in "$@"; do case $a in
    --dry-run) DRY=1 ;; --yes) YES=1 ;; --no-build) BUILD=0 ;; --no-ruby) RUBY=0 ;;
    --only-config) ONLY_CFG=1 ;;
    *)
        echo "unknown flag: $a"
        exit 2
        ;;
    esac done

G=$'\e[32m'
Y=$'\e[33m'
R=$'\e[31m'
B=$'\e[1m'
N=$'\e[0m'
step() {
    echo
    echo "${B}== $1 ==${N}"
}
info() { echo "  ${G}ok${N}    $1"; }
note() { echo "  ${Y}note${N}  $1"; }
die() {
    echo "  ${R}stop${N}  $1"
    exit 1
}
act() {
    local d=$1
    shift
    if [ $DRY = 1 ]; then echo "  would  $d"; else "$@" >/dev/null 2>&1 && info "$d" || note "$d (nothing to do or failed)"; fi
}
rm_() { act "remove: $*" git rm -rq --ignore-unmatch -- "$@"; }

# ------------------------------------------------------------------ config edits
edit_config() {
    [ -f "$CFG" ] || die "$CFG not found"
    P() { act "$1" perl -0pi -e "$2" "$CFG"; }
    P "description" 's/^description: >\n(?![ \t])/description: >\n  '"${BLOG_DESC//\//\\/}"'\n/m'
    P "protect_email: true" 's/^protect_email: false/protect_email: true/m'
    P "blog_name" 's/^blog_name: al-folio/blog_name: '"$BLOG_NAME"'/m'
    P "blog_description" 's/^blog_description: a simple whitespace theme for academics/blog_description: Cybersecurity learning log/m'
    P "disqus_shortname cleared" 's/^disqus_shortname:[ \t]*al-folio/disqus_shortname:/m'
    P "external_sources removed" 's/^# External sources\.\n(?:#.*\n)*external_sources:\n(?:[ \t]+.*\n|[ \t]*\n)*//m; s/^external_sources:\n(?:[ \t]+.*\n|[ \t]*\n)*//m'
    P "jekyll-archives books removed" 's/^  books:\n    enabled:.*\n//m'
    P "collection books removed" 's/^  books:\n    output: true\n//m'
    P "collection news removed" 's/^  news:\n    defaults:\n      layout: post\n    output: true\n//m'
    P "collection teachings removed" 's/^  teachings:\n    output: true\n//m'
    # about page: the news/announcements block needs the news collection
    if [ -f _pages/about.md ] && [ $DRY = 0 ]; then
        perl -0pi -e 's/(announcements:\s*\n\s*enabled:\s*)true/${1}false/' _pages/about.md 2>/dev/null && info "about.md: announcements disabled"
    fi
}

if [ $ONLY_CFG = 1 ]; then
    step "config only"
    edit_config
    exit 0
fi

# ------------------------------------------------------------------ preflight
[ -d .git ] && [ -f _config.yml ] || die "run this from the repo root"
step "Plan"
cat <<EOF
  1. tag current commit as pre-cleanup (rollback point)
  2. install ruby/bundler (pacman) if missing, run bundle install
  3. edit _config.yml (description, protect_email, blog name, drop demo collections/feeds)
  4. delete demo content and big files, replace Einstein resume/cv with minimal stubs
  5. delete upstream maintenance workflows (keeps pages.yml and codeql.yml)
  6. build check after each batch (nothing is committed; you review and commit)
EOF
[ $DRY = 1 ] && note "dry run: nothing will be changed"
if [ $DRY = 0 ] && [ $YES = 0 ]; then
    read -rp "Continue? [y/N] " a
    [[ $a == [yY]* ]] || exit 0
fi
if [ $DRY = 0 ] && [ -n "$(git status --porcelain)" ]; then
    die "working tree has uncommitted changes; commit or stash them first"
fi
act "tag pre-cleanup" git tag -f pre-cleanup

# ------------------------------------------------------------------ ruby
step "Ruby and bundler"
if ! command -v bundle >/dev/null 2>&1 && [ $RUBY = 1 ] && command -v pacman >/dev/null 2>&1; then
    act "pacman -S ruby base-devel" sudo pacman -S --needed --noconfirm ruby base-devel
fi
CAN_BUILD=0
if command -v bundle >/dev/null 2>&1 && [ $BUILD = 1 ]; then
    act "bundle config path vendor/bundle" bundle config set --local path vendor/bundle
    git check-ignore -q vendor/bundle || { [ $DRY = 0 ] && printf 'vendor/\n.bundle/\n' >>.gitignore; }
    act "bundle install" bundle install
    [ -f package-lock.json ] && command -v npm >/dev/null 2>&1 && act "npm ci" npm ci --silent
    CAN_BUILD=1
else
    note "no bundler (or --no-build): skipping local build checks"
fi
build_check() {
    [ $CAN_BUILD = 1 ] && [ $DRY = 0 ] || return 0
    if bundle exec jekyll build -q >/tmp/jekyll-build.log 2>&1; then
        info "build passes: $1"
    else
        grep -nE "Liquid Exception|Error:|error:|cannot load|No such file" /tmp/jekyll-build.log | grep -v "^[0-9]*:[[:space:]]*from " | head -5
        die "build failed after '$1'. Full log: /tmp/jekyll-build.log. Roll back: git reset --hard pre-cleanup"
    fi
}
# ------------------------------------------------------------------ bibliography off
step "Disable bibliography / publications"
[ -f _pages/about.md ] && act "about.md: selected_papers false" perl -0pi -e 's/^selected_papers:[ \t]*true/selected_papers: false/m' _pages/about.md
act "config: bib_search off" perl -0pi -e 's/^bib_search:[ \t]*true/bib_search: false/m' "$CFG"
act "config: publication badges off" perl -0pi -e 's/^(  (?:altmetric|dimensions|google_scholar|inspirehep):)[ \t]*true/${1} false/mg' "$CFG"
act "config: publication thumbnails off" perl -0pi -e 's/^enable_publication_thumbnails:[ \t]*true/enable_publication_thumbnails: false/m' "$CFG"
rm_ _pages/publications.md assets/bibliography _bibliography
step "Baseline build"
build_check "baseline"

# ------------------------------------------------------------------ batch 1: config
step "Batch 1: _config.yml"
edit_config
build_check "config edits"

# ------------------------------------------------------------------ batch 2: content
step "Batch 2: demo content and big files"
rm_ _books _news _teachings lighthouse_results assets/audio assets/img/book_covers assets/img/publication_preview
rm_ _pages/about_einstein.md _pages/books.md _pages/teaching.md _pages/publications.md _pages/news.md \
    _pages/plugins.md _pages/profiles.md _pages/dropdown.md
rm_ assets/rendercv/rendercv_output/Albert_Einstein_CV.pdf assets/pdf/example_pdf.pdf \
    assets/video/tutorial_al_folio.mp4 assets/plotly/demo.html assets/html/relativity.html \
    assets/img/prof_pic_color.png assets/img/rhino.png assets/img/template_error.png
rm_ '_posts/20*.md' '_projects/[0-9]*_project.md'
if [ $DRY = 0 ]; then
    printf '{\n  "basics": { "name": "Bohdan K" }\n}\n' >assets/json/resume.json && info "resume.json replaced with stub"
    printf -- '- title: General Information\n  type: map\n  contents:\n    - name: Name\n      value: Bohdan K\n' >_data/cv.yml && info "cv.yml replaced with stub"
else echo "  would  replace assets/json/resume.json and _data/cv.yml with stubs"; fi
build_check "demo content removed"

# ------------------------------------------------------------------ batch 3: data files
step "Batch 3: demo data files"
rm_ _data/citations.yml _data/coauthors.yml _data/venues.yml _data/featured_plugins.yml
if [ $CAN_BUILD = 1 ] && [ $DRY = 0 ] && ! bundle exec jekyll build -q >/tmp/jekyll-build.log 2>&1; then
    note "build broke after removing _data files; restoring them"
    git checkout pre-cleanup -- _data/citations.yml _data/coauthors.yml _data/venues.yml _data/featured_plugins.yml 2>/dev/null
    build_check "data files restored"
fi

# ------------------------------------------------------------------ batch 4: workflows
step "Batch 4: upstream workflows"
for w in star-history update-citations lighthouse-badger visual-regression update-screenshots render-cv \
    deploy-docker-tag deploy-image docker-slim prettier-comment-on-pr prettier prettier-html \
    upgrade-check update-tocs release stale axe broken-links broken-links-site \
    copilot-setup-steps unit-tests; do
    rm_ ".github/workflows/$w.yml"
done
rm_ .github/workflows/schedule-posts.txt .github/ISSUE_TEMPLATE .github/agents .github/instructions \
    .github/copilot-instructions.md .github/GIT_WORKFLOW.md .github/pull_request_template.md .github/release.yml
if [ -f .github/workflows/pages.yml ]; then
    rm_ .github/workflows/deploy.yml
else note "pages.yml not found; keeping deploy.yml"; fi

# ------------------------------------------------------------------ done
step "Done"
[ $DRY = 1 ] && {
    echo "Dry run finished; re-run without --dry-run to apply."
    exit 0
}
echo "Rollback point: git reset --hard pre-cleanup"
echo "Next: review with git status / git diff --cached, edit _pages/about.md and _data/socials.yml,"
echo "then: bash preflight.sh && git add -A && git commit -m \"Clean up\" && git push"
