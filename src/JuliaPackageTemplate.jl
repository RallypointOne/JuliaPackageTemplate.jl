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
    joinpath("docs", "_version-selector.html"),
    joinpath("docs", "assets", "styles.css"),
    joinpath("docs", "assets", "theme.scss"),
    joinpath("docs", "resources", "changelog.qmd"),
]

# Files copied with text substitution (JuliaPackageTemplate → pkg, etc.)
const TEMPLATE_FILES = [
    joinpath("docs", "Project.toml"),
    joinpath("docs", "api.qmd"),
    joinpath("docs", "resources", "coverage.qmd"),
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
    if isempty(authors)
        name = strip(readchomp(`git config user.name`))
        email = strip(readchomp(`git config user.email`))
        authors = isempty(email) ? [name] : ["$name <$email>"]
    end
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

    # --- Generated files ---
    authors_toml = join(("\"$a\"" for a in authors), ", ")

    _write("Project.toml", """
name = "$pkg"
uuid = "$new_uuid"
version = "0.1.0"
authors = [$authors_toml]

[compat]
julia = "1"
""")

    _write(joinpath("src", "$pkg.jl"), """
module $pkg

end # module
""")

    _write(joinpath("test", "Project.toml"), """
[deps]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
""")

    _write(joinpath("test", "runtests.jl"), """
using $pkg
using Test

@testset "$pkg.jl" begin
end
""")

    _write("README.md", """
[![CI](https://github.com/$owner/$pkg.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/$owner/$pkg.jl/actions/workflows/CI.yml)
[![Docs Build](https://github.com/$owner/$pkg.jl/actions/workflows/Docs.yml/badge.svg)](https://github.com/$owner/$pkg.jl/actions/workflows/Docs.yml)
[![Stable Docs](https://img.shields.io/badge/docs-stable-blue)](https://$owner.github.io/$pkg.jl/stable/)
[![Dev Docs](https://img.shields.io/badge/docs-dev-blue)](https://$owner.github.io/$pkg.jl/dev/)

# $pkg.jl
""")

    _write(joinpath("docs", "index.qmd"), """
---
title: "$pkg.jl"
---

Welcome to the documentation for **$pkg.jl**.

## Overview

$pkg.jl is a Julia package that ...

## Quickstart

```{julia}
println("Hello, World!")
```
""")

    _write("CHANGELOG.md", "## Unreleased\n")

    # CLAUDE.md — copy from template, strip Package Setup section (handled by generate)
    claude = read(joinpath(template_dir, "CLAUDE.md"), String)
    claude = replace(claude, r"# Package Setup\n.*?(?=\n# )"s => "")
    _write("CLAUDE.md", claude)

    # LICENSE
    _write("LICENSE", """
MIT License

Copyright (c) $(year(today())) $(join(authors, ", "))

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
""")

    # Initialize git repo
    run(`git -C $path init -q`)
    run(`git -C $path add -A`)
    run(`git -C $path commit -q -m "Initial commit from JuliaPackageTemplate"`)

    # Create GitHub repo and configure
    if visibility != "none"
        repo_slug = "$owner/$pkg.jl"
        homepage = "https://$owner.github.io/$pkg.jl/"
        run(`gh repo create $repo_slug --$visibility --source $path --push`)
        # Create empty gh-pages branch so Pages can be enabled
        empty_tree = strip(String(read(pipeline(devnull, `git -C $path mktree`))))
        sha = strip(String(read(`git -C $path commit-tree $empty_tree -m "Initialize gh-pages"`)))
        run(`git -C $path push -q origin $sha:refs/heads/gh-pages`)
        pages_ok = try
            run(`gh api repos/$repo_slug/pages -X POST -f source.branch=gh-pages -f source.path=/ -f build_type=legacy`)
            true
        catch
            try run(`gh api repos/$repo_slug/pages -X PUT -f source.branch=gh-pages -f source.path=/ -f build_type=legacy`); true catch; false end
        end
        pages_ok || @warn "Could not enable GitHub Pages — enable manually from repo settings"
        run(`gh repo edit $repo_slug --homepage $homepage`)
        try run(`gh api repos/$repo_slug/environments/github-pages -X DELETE`) catch end
        run(pipeline(`gh api repos/$repo_slug -X PATCH -F has_deployments=false`, devnull))
    end

    @info "Generated $pkg.jl" path owner authors visibility
    return path
end

end # module
