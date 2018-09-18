using StataDTAFiles, Test
using StataDTAFiles: LSF, verifytag, readheader, readmap,
    read_variable_types, read_variable_names, read_sortlist, read_formats

testdata = joinpath(@__DIR__, "data", "testdata.dta")

@testset "reading tags" begin
    @test verifytag(IOBuffer("<atag>"), "atag") == nothing
    @test verifytag(IOBuffer("</btag>"), "btag", true) == nothing
    @test_throws ErrorException verifytag(IOBuffer("noopening>"), "noopening")
    @test_throws EOFError verifytag(IOBuffer("<eof"), "eof")
    @test_throws ErrorException verifytag(IOBuffer("<a>"), "b")
end

@testset "reading header" begin
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
    varnames = read_variable_names(boio, hdr, map)
    @test varnames == ["a", "b", "c"]
    @test read_sortlist(boio, hdr, map) == []
    @test read_formats(boio, hdr, map) == ["%9.0g", "%9.0g", "%9s"]
    ri = rows_iterator(boio, hdr, map)
    @test collect(ri) == [(Float32(i), i, string(i)) for i in 1:10]
    close(io)
end
