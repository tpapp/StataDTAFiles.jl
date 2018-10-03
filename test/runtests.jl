using StataDTAFiles, Test
using StataDTAFiles: LSF, verifytag, read_header, read_map, read_variable_types,
    read_variable_names, read_sortlist, read_formats

testdata = joinpath(@__DIR__, "data", "testdata.dta")

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
    @test dtatypes(dta) == (Float32, Int16, StrFs{2})
    @test vartypes(dta) == (Union{Missing, Float32}, Union{Missing, Int16}, String)
    @test eltype(dta) == Tuple{vartypes(dta)...}
    @test dta.variable_names == (:a, :b, :c)
    @test dta.sortlist == []
    @test dta.formats == ["%9.0g", "%9.0g", "%9s"]
    @test all(collect(dta) .≡ [(i > 7 ? missing : Float32(i),
                                i ≤ 2 ? missing : Int16(i),
                                string(i)) for i in 1:10])
    close(dta)
end
