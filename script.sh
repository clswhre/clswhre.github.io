#!/usr/bin/env bash
# preflight.sh - checks what your al-folio blog NEEDS and what it should NOT have.
# Run from the repo root:  bash preflight.sh
# Read-only: it never changes anything, it only reports.

PASS=0
WARN=0
FAIL=0
G=$'\e[32m'
Y=$'\e[33m'
R=$'\e[31m'
B=$'\e[1m'
N=$'\e[0m'
ok() {
    echo "  ${G}PASS${N}  $1"
    PASS=$((PASS + 1))
}
warn() {
    echo "  ${Y}WARN${N}  $1"
    WARN=$((WARN + 1))
}
bad() {
    echo "  ${R}FAIL${N}  $1"
    FAIL=$((FAIL + 1))
}
hdr() {
    echo
    echo "${B}== $1 ==${N}"
}
cfg() { grep -E "^$1:" _config.yml 2>/dev/null | head -1 | sed -E "s/^$1:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^[\"']//; s/[\"']$//"; }

[ -f _config.yml ] || {
    echo "${R}Run this from the repo root (no _config.yml here).${N}"
    exit 2
}

# ---------------------------------------------------------------- NEED
hdr "NEED: local tools"
for t in git ruby bundle node npm gh convert; do
    if command -v "$t" >/dev/null 2>&1; then
        ok "$t installed"
    else
        case $t in
        convert) warn "convert (ImageMagick) missing; _config.yml has imagemagick enabled: true" ;;
        gh) warn "gh (GitHub CLI) missing; optional but handy" ;;
        *) bad "$t missing" ;;
        esac
    fi
done
if command -v ruby >/dev/null 2>&1; then
    rv=$(ruby -e 'print RUBY_VERSION')
    [[ $rv == 3.[2-9]* || $rv == [4-9].* ]] && ok "ruby $rv" || warn "ruby $rv (3.2+ recommended)"
fi

hdr "NEED: git and GitHub"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ok "inside a git repo"
    branch=$(git branch --show-current)
    [ "$branch" = main ] && ok "branch is main" || warn "branch is '$branch' (workflow triggers on main)"
    remote=$(git remote get-url origin 2>/dev/null)
    if [ -z "$remote" ]; then
        bad "no origin remote"
    else
        case $remote in
        git@github.com:*) ok "origin uses SSH ($remote)" ;;
        https://*) warn "origin uses HTTPS; switch: git remote set-url origin git@github.com:USER/REPO.git" ;;
        esac
        if [[ $remote =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
            ruser=${BASH_REMATCH[1]}
            rrepo=${BASH_REMATCH[2]%.git}
            [ "${ruser,,}" != alshedivat ] && ok "origin is not upstream al-folio" || bad "origin still points at upstream alshedivat"
            url=$(cfg url)
            if [[ $url == *.github.io ]]; then
                want="${url#https://}"
                [ "${rrepo,,}" = "${want,,}" ] && ok "repo name matches url ($rrepo)" || bad "repo '$rrepo' does not match url '$url'"
            fi
        fi
    fi
    em=$(git config user.email)
    if [[ $em == *@users.noreply.github.com ]]; then
        ok "git user.email is a GitHub noreply address"
    else warn "git user.email is '${em:-unset}' (use your noreply address or pushes can be rejected, GH007)"; fi
    last=$(git log -1 --format=%ae 2>/dev/null)
    [[ -z $last || $last == *@users.noreply.github.com ]] || warn "latest commit author is '$last' (not noreply)"
else
    bad "not a git repo"
fi

hdr "NEED: build files"
for f in Gemfile Gemfile.lock package.json _pages/about.md _data/socials.yml _data/cv.yml; do
    [ -f "$f" ] && ok "$f exists" || bad "$f missing"
done
[ -f package-lock.json ] && ok "package-lock.json exists (workflow can use npm ci)" || warn "package-lock.json missing"
if [ -f Gemfile.lock ]; then
    grep -qE '^\s+x86_64-linux' Gemfile.lock && ok "Gemfile.lock has x86_64-linux platform" ||
        bad "Gemfile.lock lacks x86_64-linux; run: bundle lock --add-platform x86_64-linux"
fi

hdr "NEED: _config.yml values"
[ "$(cfg theme)" = al_folio_core ] && ok "theme is al_folio_core" || warn "theme is '$(cfg theme)'"
[ -z "$(cfg baseurl)" ] && ok "baseurl is empty (correct for a user site)" || warn "baseurl is '$(cfg baseurl)'"
url=$(cfg url)
[ -n "$url" ] && ok "url = $url" || bad "url not set"
t=$(cfg title)
{ [ -n "$t" ] && [ "$t" != blank ]; } && ok "title = $t" || warn "title is '${t:-empty}' (placeholder)"
[ -n "$(cfg description | tr -d '>')" ] && ok "description set" || warn "description empty"
[ "$(cfg protect_email)" = true ] && ok "protect_email: true" || warn "protect_email is false (email is scrapeable)"

hdr "NEED: deploy workflow"
wf=$(grep -lE 'actions/deploy-pages' .github/workflows/*.yml 2>/dev/null | head -1)
if [ -n "$wf" ]; then
    ok "Pages deploy workflow: $wf"
    grep -q 'upload-pages-artifact' "$wf" && ok "uploads Pages artifact" || bad "no upload-pages-artifact step"
    grep -q 'bundle exec jekyll build' "$wf" && ok "builds with bundle exec jekyll build" || bad "no 'bundle exec jekyll build'"
    rvw=$(grep -oE "ruby-version: *['\"]?[0-9.]+" "$wf" | grep -oE '[0-9.]+$' | head -1)
    [[ $rvw == 3.[2-9]* ]] && ok "workflow ruby $rvw" || warn "workflow ruby '${rvw:-unset}' (use 3.3)"
    grep -qE 'setup-node' "$wf" && ok "workflow sets up node (Tailwind)" || warn "workflow has no setup-node/npm ci; add it if Tailwind CSS is missing"
else
    bad "no workflow using actions/deploy-pages in .github/workflows/"
fi

hdr "NEED: custom domain (only if used)"
if [[ $url == https://* && $url != *.github.io ]]; then
    [ -f CNAME ] && ok "CNAME exists" || bad "CNAME missing for custom domain"
    [ -f CNAME ] && [ "$(tr -d '[:space:]' <CNAME)" = "${url#https://}" ] && ok "CNAME matches url" || warn "CNAME does not match url"
    grep -qE 'keep_files' _config.yml && ok "keep_files set" || warn "keep_files missing"
else
    ok "using github.io URL (no CNAME needed)"
fi

# ---------------------------------------------------------------- DON'T
hdr "DON'T: demo content that should be gone"
for p in _books _news _teachings lighthouse_results assets/img/book_covers assets/img/publication_preview \
    _pages/about_einstein.md _pages/books.md _pages/teaching.md _pages/publications.md \
    assets/rendercv/rendercv_output/Albert_Einstein_CV.pdf assets/pdf/example_pdf.pdf \
    assets/video/tutorial_al_folio.mp4 assets/plotly/demo.html assets/html/relativity.html \
    assets/audio _data/citations.yml _data/coauthors.yml _data/venues.yml _data/featured_plugins.yml; do
    [ -e "$p" ] && warn "still present: $p" || ok "gone: $p"
done
n=$(ls _posts/20{15,18,20,21,22,23,24,25}-*.md 2>/dev/null | wc -l)
[ "$n" -gt 0 ] && warn "$n sample posts still in _posts/ (al-folio demos)" || ok "no al-folio sample posts"
n=$(ls _projects/[0-9]*_project.md 2>/dev/null | wc -l)
[ "$n" -gt 0 ] && warn "$n demo projects still in _projects/" || ok "no demo projects"

hdr "DON'T: leftover Einstein/al-folio values in config"
grep -qE 'last_name: *\[Einstein\]' _config.yml && warn "scholar still set to Einstein" || ok "scholar not Einstein"
grep -qE '^disqus_shortname: *al-folio' _config.yml && warn "disqus_shortname still al-folio" || ok "disqus_shortname cleared"
grep -q 'medium.com/@al-folio' _config.yml && warn "external_sources still pulls al-folio's Medium feed" || ok "no al-folio external feed"
grep -q 'blog_name: *al-folio' _config.yml && warn "blog_name still al-folio" || ok "blog_name changed"
grep -qi einstein assets/json/resume.json 2>/dev/null && warn "assets/json/resume.json is still Einstein's" || ok "resume.json not Einstein's"
grep -qi einstein _data/cv.yml 2>/dev/null && warn "_data/cv.yml still mentions Einstein" || ok "cv.yml not Einstein's"
grep -qE '[A-Za-z0-9._-]+@[A-Za-z0-9.-]+' <(sed -n '/^contact_note:/,/^description:/p' _config.yml) &&
    [ "$(cfg protect_email)" != true ] && warn "plain email in contact_note with protect_email off"

hdr "DON'T: upstream maintenance workflows"
for w in star-history update-citations lighthouse-badger visual-regression update-screenshots render-cv \
    deploy-docker-tag deploy-image docker-slim prettier-comment-on-pr upgrade-check update-tocs release stale; do
    [ -f ".github/workflows/$w.yml" ] && warn "upstream workflow present: $w.yml" || ok "absent: $w.yml"
done
grep -lq 'jekyll-build-pages' .github/workflows/*.yml 2>/dev/null &&
    bad "a workflow uses actions/jekyll-build-pages (cannot build al-folio)" || ok "no jekyll-build-pages workflow"

hdr "DON'T: secrets and junk in the repo (security)"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    hits=$(git grep -nIE 'BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}' 2>/dev/null | head -5)
    [ -z "$hits" ] && ok "no obvious keys/tokens in tracked files" || {
        bad "possible secrets tracked:"
        echo "$hits" | sed 's/^/        /'
    }
    s=$(git ls-files | grep -E '(^|/)(\.env(\..*)?|id_(rsa|ed25519|ecdsa)|.*\.pem|.*\.p12|\.netrc)$')
    [ -z "$s" ] && ok "no .env/key files tracked" || { bad "sensitive files tracked: $s"; }
    big=$(git ls-files -z | xargs -0 -r stat -c '%s %n' 2>/dev/null | awk '$1>5242880 {printf "%.1fMB %s\n",$1/1048576,substr($0,index($0,$2))}')
    [ -z "$big" ] && ok "no tracked files over 5 MB" || {
        warn "large tracked files:"
        echo "$big" | sed 's/^/        /'
    }
    [ -d _site ] && ! git check-ignore -q _site && warn "_site/ exists and is not gitignored"
fi

# ---------------------------------------------------------------- SUMMARY
echo
echo "${B}Summary:${N} ${G}$PASS pass${N}, ${Y}$WARN warn${N}, ${R}$FAIL fail${N}"
[ "$FAIL" -gt 0 ] && echo "Fix the FAILs first; they will break the build or the push."
[ "$FAIL" -eq 0 ] && [ "$WARN" -gt 0 ] && echo "No blockers. WARNs are cleanup or hardening."
[ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ] && echo "All clear. Commit, push, and watch the Actions tab."
exit $((FAIL > 0 ? 1 : 0))
