using StataDTAFiles, Test
using StataDTAFiles: LSF, verifytag, readheader, readmap, read_variable_types

@testset "reading tags" begin
    @test verifytag(IOBuffer("<atag>"), "atag") == nothing
    @test verifytag(IOBuffer("</btag>"), "btag", true) == nothing
    @test_throws ErrorException verifytag(IOBuffer("noopening>"), "noopening")
    @test_throws EOFError verifytag(IOBuffer("<eof"), "eof")
    @test_throws ErrorException verifytag(IOBuffer("<a>"), "b")
end

@testset "reading header" begin
    testdata = joinpath(@__DIR__, "data", "testdata.dta")
    io = open(testdata, "r")
    verifytag(io, "stata_dta")
    hdr, boio = readheader(io)
    @test hdr.release == 118
    @test hdr.byteorder ≡ LSF()
    @test hdr.variables == 3
    @test hdr.observations == 10
    @test hdr.label == ""
    map = readmap(boio)
    @test map.eof == filesize(testdata)
    vartypes = read_variable_types(boio, hdr, map)
    @test vartypes == (Float32, Int16, StrFs{2})
    close(io)
end
