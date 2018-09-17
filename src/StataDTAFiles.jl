module StataDTAFiles

using ArgCheck: @argcheck
using DocStringExtensions: SIGNATURES

"""
$(SIGNATURES)

Read `"<tag>"` from `io` as `"tag"`. For closing tags, the initial `'/'` is included.

Throw an error after `maxbytes` bytes are read.
"""
function readtag(io::IO; maxbytes = 128)
    lt = read(io, UInt8)
    lt == UInt8('<') || error("First byte is not a '<'.")
    content = Vector{UInt8}()
    bytecount = 0
    while !eof(io) && bytecount < maxbytes
        c = read(io, UInt8)
        if c == UInt8('>')
            return String(content)
        else
            push!(content, c)
            bytecount += 1
        end
    end
    msg = eof(io) ? "Reached end of file" : "Read $(bytecount) bytes"
    error("$(msg) without finding a closing '>'.")
end

## FIXME this could be much faster, not required to read
verifytag(io::IO, tag, closing = false) = @assert readtag(io) == (closing ? "/" * tag : tag)

function verifytag(f, io::IO, tag)
    verifytag(io, tag)
    result = f(io)
    verifytag(io, tag, true)
    result
end

readfixed(io::IO, nb) = String(read!(io, Vector{UInt8}(undef, nb)))

abstract type ByteOrder end

struct MSF <: ByteOrder end     # big-endian

struct LSF <: ByteOrder end     # little-endian

readnum(io::IO, ::MSF, T) = ntoh(read(io, T))

readnum(io::IO, ::LSF, T) = ltoh(read(io, T))

function readbyteorder(io::IO)
    verifytag(io, "byteorder") do io
        order = readfixed(io, 3)
        if order == "MSF"
            MSF()
        elseif order == "LSF"
            LSF()
        else
            error("unknown byte order $(order)")
        end
    end
end

function readstrfs(io::IO, byteorder, T)
    len = Int(readnum(io, byteorder, T))
    buffer = Vector{UInt8}(undef, len)
    read!(io, buffer)
    numchars = findfirst(isequal(0x00), buffer)
    if numchars ≢ nothing
        resize!(buffer, numchars)
    end
    String(buffer)
end

struct DTAHeader{B <: ByteOrder}
    release::Int
    byteorder::B
    variables::Int
    observations::Int
    label::String
    timestamp::String           # FIXME parse date in timestamp
end

function readheader(io::IO)
    verifytag(io, "header") do io
        @assert verifytag(io -> readfixed(io, 3), io, "release") == "118"
        byteorder = readbyteorder(io)
        K = verifytag(io -> readnum(io, byteorder, Int16), io, "K")
        N = verifytag(io -> readnum(io, byteorder, Int64), io, "N")
        label = verifytag(io -> readstrfs(io, byteorder, Int16), io, "label")
        timestamp = verifytag(io -> readstrfs(io, byteorder, Int8), io, "timestamp")
        DTAHeader(118, byteorder, Int(K), Int(N), label, timestamp)
    end
end

struct DTAMap
    stata_data_open::Int64
    map::Int64
    variable_types::Int64
    varnames::Int64
    sortlist::Int64
    formats::Int64
    value_label_names::Int64
    variable_labels::Int64
    characteristics::Int64
    data::Int64
    strls::Int64
    value_labels::Int64
    stata_data_close::Int64
    eof::Int64
end

function readmap(io::IO, byteorder::ByteOrder)
    verifytag(io, "map") do io
        map = DTAMap([readnum(io, byteorder, Int64) for _ in 1:14]...)
        @assert map.stata_data_open == 0
        map
    end
end

end # module
