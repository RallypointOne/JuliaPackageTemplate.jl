using JuliaPackageTemplate
using Test

@testset "JuliaPackageTemplate.jl" begin
    @testset "generate" begin
        mktempdir() do dir
            pkg_path = generate("testowner/TestPkg.jl"; path=joinpath(dir, "TestPkg"), visibility="none")
            @test isdir(pkg_path)
            @test isfile(joinpath(pkg_path, "Project.toml"))
            @test isfile(joinpath(pkg_path, "src", "TestPkg.jl"))
            @test isfile(joinpath(pkg_path, "test", "runtests.jl"))
            @test isfile(joinpath(pkg_path, "CLAUDE.md"))
            @test isfile(joinpath(pkg_path, "README.md"))
            @test isfile(joinpath(pkg_path, "LICENSE"))
            @test isfile(joinpath(pkg_path, ".github", "workflows", "CI.yml"))

            proj = read(joinpath(pkg_path, "Project.toml"), String)
            @test contains(proj, "name = \"TestPkg\"")
            @test !contains(proj, "JuliaPackageTemplate")
            @test !contains(proj, JuliaPackageTemplate.TEMPLATE_UUID)
        end
    end
end
