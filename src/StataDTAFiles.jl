module StataDTAFiles

using ArgCheck: @argcheck
using DocStringExtensions: SIGNATURES

"""
$(SIGNATURES)

Read `"<tag>"` and `"</tag>"` from `io` as `"tag", false` or `"tag", true`, respectively.

Throw an error after `maxbytes` bytes are read.
"""
function readtag(io::IO; maxbytes = 128)
    lt = read(io, UInt8)
    lt == UInt8('<') || error("First byte is not a '<'.")
    content = Vector{UInt8}()
    bytecount = 0
    isclosing = false
    while !eof(io) && bytecount < maxbytes
        c = read(io, UInt8)
        if bytecount == 0 && c == UInt8('/')
            isclosing = true
        elseif c == UInt8('>')
            return String(content), isclosing
        else
            push!(content, c)
            bytecount += 1
        end
    end
    msg = eof(io) ? "Reached end of file" : "Read $(bytecount) bytes"
    error("$(msg) without finding a closing '>'.")
end

end # module
