module JuliaPackageTemplate

using Dates: year, today
using UUIDs: uuid4

export generate

#--------------------------------------------------------------------------------# Package Generation
const TEMPLATE_UUID = "7adf5606-a580-4ec5-b7a7-75603f58a1cf"

# Files copied verbatim from template (no text substitution)
const VERBATIM_FILES = [
    joinpath(".github", "dependabot.yml"),
    joinpath(".github", "workflows", "CI.yml"),
    joinpath(".github", "workflows", "Docs.yml"),
    joinpath(".github", "workflows", "DocsBackfill.yml"),
    joinpath(".github", "workflows", "TagBot.yml"),
    joinpath(".github", "workflows", "dependabot-automerge.yml"),
    ".gitignore",
    joinpath("docs", ".gitignore"),
    joinpath("docs", "assets", "_version-selector.html"),
    joinpath("docs", "assets", "styles.css"),
    joinpath("docs", "assets", "theme.scss"),
]

# Files copied with text substitution (JuliaPackageTemplate → pkg, etc.)
const TEMPLATE_FILES = [
    joinpath("docs", "Project.toml"),
    joinpath("docs", "pages", "api.qmd"),
    joinpath("docs", "pages", "coverage.qmd"),
]

const RP1_LOGO = "https://github.com/user-attachments/assets/f7216152-0d6e-4459-8e65-b9ed59421638"
const RP1_LOGO_URL = "https://rallypoint1.com"

"""
    generate("owner/PackageName.jl"; path, authors)

Generate a new Julia package from the JuliaPackageTemplate.

### Arguments
- `repo`: GitHub repository in `"owner/PackageName.jl"` format.

### Keyword Arguments
- `path`: Target directory (default: `~/.julia/dev/PackageName`).
- `authors`: Package authors (default: derived from `git config user.name` and `git config user.email`).
- `visibility`: GitHub repo visibility — `"private"`, `"public"`, or `"none"` to skip repo creation (default: `"private"`).
- `logo`: URL for the docs navbar logo (default: Rallypoint One logo for `RallypointOne` repos, `nothing` otherwise).
- `logo_url`: URL the logo links to (default: `https://rallypoint1.com` for `RallypointOne` repos, `nothing` otherwise).

### Dependencies (when `visibility != "none"`)
- `git` — repo initialization and push.
- `gh` — GitHub CLI, authenticated with `repo` scope (create repos, deploy keys, secrets, Pages).
- `ssh-keygen` — generates the TagBot deploy key.

### Examples
```julia
generate("myorg/MyPackage.jl")
generate("myorg/MyPackage.jl"; path="/tmp/MyPackage", authors=["Alice", "Bob"])
```
"""
function generate(repo::AbstractString; path::AbstractString="", authors::Vector{String}=String[], visibility::AbstractString="private", logo=nothing, logo_url=nothing)
    m = match(r"^([^/]+)/([^/]+)\.jl$", repo)
    isnothing(m) && throw(ArgumentError("Expected \"owner/PackageName.jl\", got \"$repo\""))
    owner, pkg = String(m[1]), String(m[2])

    path = isempty(path) ? joinpath(homedir(), ".julia", "dev", pkg) : abspath(expanduser(path))
    git_name = try strip(readchomp(`git config user.name`)) catch; "" end
    git_email = try strip(readchomp(`git config user.email`)) catch; "" end
    if isempty(authors)
        author = if !isempty(git_name) && !isempty(git_email)
            "$git_name <$git_email>"
        elseif !isempty(git_name)
            git_name
        else
            get(ENV, "USER", get(ENV, "USERNAME", "unknown"))
        end
        authors = [author]
    end
    commit_name = isempty(git_name) ? "JuliaPackageTemplate" : git_name
    commit_email = isempty(git_email) ? "noreply@example.com" : git_email
    visibility in ("private", "public", "none") || throw(ArgumentError("visibility must be \"private\", \"public\", or \"none\""))

    ispath(path) && error("Path already exists: $path")
    template_dir = pkgdir(@__MODULE__)
    isnothing(template_dir) && error("Cannot find JuliaPackageTemplate package directory")

    new_uuid = string(uuid4())

    function _write(relpath, content)
        fp = joinpath(path, relpath)
        mkpath(dirname(fp))
        Base.write(fp, content)
    end

    function _substitute(content)
        content = replace(content, "RallypointOne/JuliaPackageTemplate" => "$owner/$pkg")
        content = replace(content, "JuliaPackageTemplate" => pkg)
        content = replace(content, TEMPLATE_UUID => new_uuid)
        content = replace(content, r"Built on \d{4}-\d{2}-\d{2}" => "Built on __BUILD_DATE__")
        return content
    end

    # --- Verbatim copies ---
    for f in VERBATIM_FILES
        _write(f, read(joinpath(template_dir, f), String))
    end

    # --- Template copies (with substitution) ---
    for f in TEMPLATE_FILES
        _write(f, _substitute(read(joinpath(template_dir, f), String)))
    end

    # docs/_quarto.yml — substitution + logo handling
    quarto = _substitute(read(joinpath(template_dir, "docs", "_quarto.yml"), String))
    is_rp1 = startswith(owner, "RallypointOne")
    _logo = !isnothing(logo) ? logo : is_rp1 ? RP1_LOGO : nothing
    _logo_url = !isnothing(logo_url) ? logo_url : is_rp1 ? RP1_LOGO_URL : nothing
    if isnothing(_logo)
        quarto = replace(quarto, r"\n    logo: [^\n]+" => "")
    else
        quarto = replace(quarto, r"(logo: )[^\n]+" => SubstitutionString("\\1$_logo"))
    end
    if isnothing(_logo_url)
        quarto = replace(quarto, r"\n    logo-href: [^\n]+" => "")
    else
        quarto = replace(quarto, r"(logo-href: )[^\n]+" => SubstitutionString("\\1$_logo_url"))
    end
    _write(joinpath("docs", "_quarto.yml"), quarto)

    # --- Render templates/ tree ---
    authors_toml = join(("\"$a\"" for a in authors), ", ")
    placeholders = [
        "{{PKG}}"          => pkg,
        "{{OWNER}}"        => owner,
        "{{UUID}}"         => new_uuid,
        "{{AUTHORS_TOML}}" => authors_toml,
        "{{AUTHORS_TEXT}}" => join(authors, ", "),
        "{{YEAR}}"         => string(year(today())),
    ]
    _apply(s) = reduce((acc, p) -> replace(acc, p), placeholders; init=s)

    templates_dir = joinpath(template_dir, "templates")
    for (root, _, files) in walkdir(templates_dir)
        for f in files
            src = joinpath(root, f)
            rel = relpath(src, templates_dir)
            rel = replace(rel, "PKG" => pkg)
            _write(rel, _apply(read(src, String)))
        end
    end

    # CLAUDE.md — copy from template, strip Package Setup section (handled by generate)
    claude = read(joinpath(template_dir, "CLAUDE.md"), String)
    claude = replace(claude, r"# Package Setup\r?\n.*?(?=\r?\n# )"s => "")
    _write("CLAUDE.md", claude)

    # Initialize git repo
    run(`git -C $path init -q`)
    run(`git -C $path add -A`)
    run(`git -C $path -c user.name=$commit_name -c user.email=$commit_email commit -q -m "Initial commit from JuliaPackageTemplate"`)

    # Create GitHub repo and configure
    incomplete = String[]
    if visibility != "none"
        repo_slug = "$owner/$pkg.jl"
        repo_url = "https://github.com/$repo_slug"
        homepage = "https://$owner.github.io/$pkg.jl/"

        # Repo creation is not recoverable — if this fails, abort before remote state diverges.
        run(`gh repo create $repo_slug --$visibility --source $path --push`)

        _try(desc, f) = try
            f()
        catch e
            @warn "$desc failed — complete manually at $repo_url" exception=(e, catch_backtrace())
            push!(incomplete, desc)
        end

        _try("push gh-pages branch") do
            empty_tree = strip(String(read(pipeline(devnull, `git -C $path mktree`))))
            sha = strip(String(read(`git -C $path -c user.name=$commit_name -c user.email=$commit_email commit-tree $empty_tree -m "Initialize gh-pages"`)))
            run(`git -C $path push -q origin $sha:refs/heads/gh-pages`)
        end

        _try("enable GitHub Pages") do
            try
                run(`gh api repos/$repo_slug/pages -X POST -f source.branch=gh-pages -f source.path=/ -f build_type=legacy`)
            catch
                run(`gh api repos/$repo_slug/pages -X PUT -f source.branch=gh-pages -f source.path=/ -f build_type=legacy`)
            end
        end

        _try("set homepage URL") do
            run(`gh repo edit $repo_slug --homepage $homepage`)
        end

        # Best-effort only — not critical to package operation.
        try run(`gh api repos/$repo_slug/environments/github-pages -X DELETE`) catch end
        try run(pipeline(`gh api repos/$repo_slug -X PATCH -F has_deployments=false`, devnull)) catch end

        _try("install TagBot deploy key + TAGBOT_SSH secret") do
            mktempdir() do tmpdir
                keyfile = joinpath(tmpdir, "tagbot_key")
                run(`ssh-keygen -t ed25519 -f $keyfile -N "" -C tagbot -q`)
                run(`gh repo deploy-key add $(keyfile * ".pub") --repo $repo_slug --title TagBot --allow-write`)
                run(pipeline(keyfile, `gh secret set TAGBOT_SSH --repo $repo_slug`))
            end
        end
    end

    if !isempty(incomplete)
        @warn "Package generated but $(length(incomplete)) post-creation step(s) failed" path steps=incomplete
    else
        @info "Generated $pkg.jl" path owner authors visibility
    end
    return path
end

end # module
