using JuliaPackageTemplate
using Test
using YAML: YAML
using TOML: TOML

const PKG = "TestPkg"
const OWNER = "testowner"
const RP1_OWNER = "RallypointOne"

function gen(dir; owner=OWNER, pkg=PKG, kwargs...)
    generate("$owner/$pkg.jl"; path=joinpath(dir, pkg), visibility="none", kwargs...)
end

@testset "JuliaPackageTemplate.jl" begin

    @testset "argument validation" begin
        mktempdir() do dir
            @test_throws ArgumentError generate("no-slash"; path=joinpath(dir, "a"), visibility="none")
            @test_throws ArgumentError generate("owner/NoJlSuffix"; path=joinpath(dir, "b"), visibility="none")
            @test_throws ArgumentError generate("owner/Pkg.jl"; path=joinpath(dir, "c"), visibility="bogus")
        end
    end

    @testset "path already exists" begin
        mktempdir() do dir
            mkpath(joinpath(dir, "Existing"))
            @test_throws ErrorException generate("o/Existing.jl"; path=joinpath(dir, "Existing"), visibility="none")
        end
    end

    @testset "generated files exist" begin
        mktempdir() do dir
            p = gen(dir)
            for f in [
                "Project.toml", "README.md", "LICENSE", "CLAUDE.md",
                ".gitignore",
                joinpath("src", "$PKG.jl"),
                joinpath("test", "runtests.jl"),
                joinpath("test", "Project.toml"),
                joinpath(".github", "workflows", "CI.yml"),
                joinpath(".github", "workflows", "Docs.yml"),
                joinpath(".github", "workflows", "DocsBackfill.yml"),
                joinpath(".github", "workflows", "TagBot.yml"),
                joinpath(".github", "workflows", "dependabot-automerge.yml"),
                joinpath(".github", "dependabot.yml"),
                joinpath("docs", "Project.toml"),
                joinpath("docs", "_quarto.yml"),
                joinpath("docs", "index.qmd"),
                joinpath("docs", ".gitignore"),
                joinpath("docs", "pages", "api.qmd"),
                joinpath("docs", "pages", "coverage.qmd"),
                joinpath("docs", "assets", "_version-selector.html"),
                joinpath("docs", "assets", "styles.css"),
                joinpath("docs", "assets", "theme.scss"),
            ]
                @test isfile(joinpath(p, f))
            end
            @test !ispath(joinpath(p, "docs", "resources"))
            @test !isfile(joinpath(p, "docs", "pages", "changelog.qmd"))
        end
    end

    @testset "substitution" begin
        mktempdir() do dir
            p = gen(dir)
            proj = read(joinpath(p, "Project.toml"), String)
            @test contains(proj, "name = \"$PKG\"")
            @test !contains(proj, "JuliaPackageTemplate")
            @test !contains(proj, JuliaPackageTemplate.TEMPLATE_UUID)

            readme = read(joinpath(p, "README.md"), String)
            @test contains(readme, "# $PKG.jl")
            @test contains(readme, "$OWNER/$PKG.jl")
            @test !contains(readme, "JuliaPackageTemplate")

            quarto = read(joinpath(p, "docs", "_quarto.yml"), String)
            @test contains(quarto, "title: \"$PKG.jl\"")
            @test contains(quarto, "$OWNER/$PKG.jl")
            @test !contains(quarto, "JuliaPackageTemplate")

            api = read(joinpath(p, "docs", "pages", "api.qmd"), String)
            @test contains(api, "using $PKG")
            @test !contains(api, "JuliaPackageTemplate")

            index = read(joinpath(p, "docs", "index.qmd"), String)
            @test contains(index, "## Overview")
            @test contains(index, "## Quickstart")
            @test contains(index, "$PKG.jl")
        end
    end

    @testset "UUIDs are unique per call" begin
        mktempdir() do dir
            p1 = gen(dir; pkg="PkgA")
            p2 = gen(dir; pkg="PkgB")
            uuid1 = match(r"uuid = \"([^\"]+)\"", read(joinpath(p1, "Project.toml"), String))[1]
            uuid2 = match(r"uuid = \"([^\"]+)\"", read(joinpath(p2, "Project.toml"), String))[1]
            @test uuid1 != uuid2
            @test uuid1 != JuliaPackageTemplate.TEMPLATE_UUID
            @test uuid2 != JuliaPackageTemplate.TEMPLATE_UUID
        end
    end

    @testset "logo handling" begin
        mktempdir() do dir
            # RallypointOne owner → default RP1 logo
            p = gen(dir; owner=RP1_OWNER, pkg="RP1Pkg")
            q = read(joinpath(p, "docs", "_quarto.yml"), String)
            @test contains(q, "logo: $(JuliaPackageTemplate.RP1_LOGO)")
            @test contains(q, "logo-href: $(JuliaPackageTemplate.RP1_LOGO_URL)")

            # Non-RP1 owner → no logo lines
            p2 = gen(dir; pkg="NoLogo")
            q2 = read(joinpath(p2, "docs", "_quarto.yml"), String)
            @test !contains(q2, "logo:")
            @test !contains(q2, "logo-href:")

            # Explicit logo override
            p3 = gen(dir; pkg="CustomLogo", logo="https://example.com/l.png", logo_url="https://example.com")
            q3 = read(joinpath(p3, "docs", "_quarto.yml"), String)
            @test contains(q3, "logo: https://example.com/l.png")
            @test contains(q3, "logo-href: https://example.com")
        end
    end

    @testset "CLAUDE.md strips Package Setup" begin
        mktempdir() do dir
            p = gen(dir)
            claude = read(joinpath(p, "CLAUDE.md"), String)
            @test !contains(claude, "# Package Setup")
            @test !contains(claude, "generate(\"owner/PackageName.jl\")")
            @test contains(claude, "# Development")
        end
    end

    @testset "authors" begin
        mktempdir() do dir
            p = gen(dir; authors=["Alice", "Bob <bob@example.com>"])
            proj = read(joinpath(p, "Project.toml"), String)
            @test contains(proj, "authors = [\"Alice\", \"Bob <bob@example.com>\"]")
            license = read(joinpath(p, "LICENSE"), String)
            @test contains(license, "Alice, Bob <bob@example.com>")
        end
    end

    @testset "git repo initialized" begin
        mktempdir() do dir
            p = gen(dir)
            @test isdir(joinpath(p, ".git"))
            log = readchomp(`git -C $p log --oneline`)
            @test contains(log, "Initial commit from JuliaPackageTemplate")
        end
    end

    @testset "return value is package path" begin
        mktempdir() do dir
            expected = joinpath(dir, PKG)
            p = gen(dir)
            @test p == expected
        end
    end

    @testset "generated YAML/TOML parses" begin
        mktempdir() do dir
            p = gen(dir)

            # _quarto.yml parses and has expected shape
            quarto = YAML.load_file(joinpath(p, "docs", "_quarto.yml"))
            @test quarto["book"]["title"] == "$PKG.jl"
            @test any(c -> get(c, "part", "") == "API", quarto["book"]["chapters"])

            # Project files parse and carry the new values
            root_proj = TOML.parsefile(joinpath(p, "Project.toml"))
            @test root_proj["name"] == PKG
            @test root_proj["version"] == "0.1.0"
            @test length(root_proj["authors"]) >= 1

            docs_proj = TOML.parsefile(joinpath(p, "docs", "Project.toml"))
            @test haskey(docs_proj["deps"], PKG)

            test_proj = TOML.parsefile(joinpath(p, "test", "Project.toml"))
            @test haskey(test_proj["deps"], "Test")
        end
    end

    @testset "no unresolved placeholders" begin
        mktempdir() do dir
            p = gen(dir)
            for (root, _, files) in walkdir(p)
                occursin(joinpath(p, ".git"), root) && continue
                for f in files
                    path = joinpath(root, f)
                    content = try read(path, String) catch; continue end
                    @test !occursin("{{", content)
                end
            end
        end
    end

end
