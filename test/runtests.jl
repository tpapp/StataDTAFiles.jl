using StataDTAFiles
using StataDTAFiles: readtag
using Test

@testset "reading tags" begin
    @test readtag(IOBuffer("<atag>")) == ("atag", false)
    @test readtag(IOBuffer("</btag>")) == ("btag", true)
    @test_throws ErrorException readtag(IOBuffer("noopening>"))
    @test_throws ErrorException readtag(IOBuffer("<eof"))
    @test_throws ErrorException readtag(IOBuffer("<toolong"); maxbytes = 3)
end
