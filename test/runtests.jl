using StataDTAFiles, Test
using StataDTAFiles: LSF, verifytag, read_header, read_map, read_variable_types,
    read_variable_names, read_sortlist, read_formats
using StrFs

testdata = joinpath(@__DIR__, "data", "testdata.dta")

≅(a, b) = a == b
≅(a::AbstractVector, b::AbstractVector) = all(a .≅ b)
≅(a::T, b::T) where T <: Tuple = all(a .≅ b)
≅(::Missing, ::Missing) = true

@testset "reading tags" begin
    @test verifytag(IOBuffer("<atag>"), "atag") == nothing
    @test verifytag(IOBuffer("</btag>"), "btag", true) == nothing
    @test_throws ErrorException verifytag(IOBuffer("noopening>"), "noopening")
    @test_throws EOFError verifytag(IOBuffer("<eof"), "eof")
    @test_throws ErrorException verifytag(IOBuffer("<a>"), "b")
end

@testset "reading header" begin
    dta = open(DTAFile, testdata)
    @test dta.header.release == 118
    @test dta.header.variables == 3
    @test dta.header.observations == 10
    @test dta.header.label == ""
    @test dta.map.eof == filesize(testdata)
    @test dtatypes(dta) == (Float32, Int16, StrF{2})
    @test vartypes(dta) == (Union{Missing, Float32}, Union{Missing, Int16}, StrF{2})
    @test eltype(dta) == Tuple{vartypes(dta)...}
    @test dta.variable_names == (:a, :b, :c)
    @test dta.sortlist == []
    @test dta.formats == ["%9.0g", "%9.0g", "%9s"]
    @test collect(dta) ≅ [(i > 7 ? missing : Float32(i),
                           i ≤ 2 ? missing : Int16(i),
                           StrF{2}(string(i))) for i in 1:10]
    close(dta)
end

@testset "reading header" begin
    str = open(repr, DTAFile, testdata)
    r_header = raw"^Stata DTA file 118, 3 vars in 10 rows, .*\n\s+not sorted\n"
    r_vars = raw"\s+a::Float32.*\n\s+b::Int16.*\n\s+c::StrF\{2\}.*$"
    @test occursin(Regex(r_header * r_vars), str)
end
