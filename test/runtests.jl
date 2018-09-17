using StataDTAFiles, Test
using StataDTAFiles: readtag, verifytag, readheader, readmap, LSF

@testset "reading tags" begin
    @test readtag(IOBuffer("<atag>")) == "atag"
    @test readtag(IOBuffer("</btag>")) == "/btag"
    @test_throws ErrorException readtag(IOBuffer("noopening>"))
    @test_throws ErrorException readtag(IOBuffer("<eof"))
    @test_throws ErrorException readtag(IOBuffer("<toolong"); maxbytes = 3)
end

@testset "reading header" begin
    testdata = joinpath(@__DIR__, "data", "testdata.dta")
    io = open(testdata, "r")
    verifytag(io, "stata_dta")
    hdr = readheader(io)
    @test hdr.release == 118
    @test hdr.byteorder ≡ LSF()
    @test hdr.variables == 3
    @test hdr.observations == 10
    @test hdr.label == ""
    map = readmap(io, hdr.byteorder)
    @test map.eof == filesize(testdata)
    close(io)
end
