module StataDTAFiles

using ArgCheck: @argcheck
using DocStringExtensions: SIGNATURES

import Base: read, seek

export StrFs


# types for byteorder handling and IO wrapper

abstract type ByteOrder end

struct MSF <: ByteOrder end     # big-endian

struct LSF <: ByteOrder end     # little-endian

struct ByteOrderIO{B <: ByteOrder, T <: IO} <: IO
    byteorder::B
    io::T
end

read(io::ByteOrderIO, ::Type{UInt8}) = read(io.io, UInt8)

seek(io::ByteOrderIO, pos) = seek(io.io, pos)


# tag verification

# """
# $(SIGNATURES)

# Read `"<tag>"` from `io` as `"tag"`. For closing tags, the initial `'/'` is included.

# Throw an error after `maxbytes` bytes are read.
# """
# function readtag(io::IO; maxbytes = 128)
#     lt = read(io, UInt8)
#     lt == UInt8('<') || error("First byte is not a '<'.")
#     content = Vector{UInt8}()
#     bytecount = 0
#     while !eof(io) && bytecount < maxbytes
#         c = read(io, UInt8)
#         if c == UInt8('>')
#             return String(content)
#         else
#             push!(content, c)
#             bytecount += 1
#         end
#     end
#     msg = eof(io) ? "Reached end of file" : "Read $(bytecount) bytes"
#     error("$(msg) without finding a closing '>'.")
# end

function verifytag(io::IO, tag::AbstractArray{UInt8}, closing::Bool = false)
    read(io, UInt8) == UInt8('<') || error("First byte is not a '<'.")
    if closing
        read(io, UInt8) == UInt8('/') || error("/ expected (closing tag).")
    end
    for c in tag
        read(io, UInt8) == c || error("not the expected tag.")
    end
    read(io, UInt8) == UInt8('>') || error("Tag not closed with '>'.")
    nothing
end

verifytag(io::IO, tag::String, closing::Bool = false) = verifytag(io, codeunits(tag), closing)

function verifytag(f, io::IO, tag)
    verifytag(io, tag)
    result = f(io)
    verifytag(io, tag, true)
    result
end

readfixedstring(io::IO, nb) = String(read!(io, Vector{UInt8}(undef, nb)))



function readbyteorder(io::IO)
    verifytag(io, "byteorder") do io
        order = readfixedstring(io, 3)
        if order == "MSF"
            MSF()
        elseif order == "LSF"
            LSF()
        else
            error("unknown byte order $(order)")
        end
    end
end

readnum(boio::ByteOrderIO{MSF}, T) = ntoh(read(boio.io, T))

readnum(boio::ByteOrderIO{LSF}, T) = ltoh(read(boio.io, T))

"""
$(SIGNATURES)

Read chars into a buffer of length `len`, find the terminating "\0" (if any) and truncate,
returning a string.
"""
function readchompedstring(boio::ByteOrderIO, len::Integer)
    buffer = Vector{UInt8}(undef, len)
    read!(boio.io, buffer)
    numchars = findfirst(isequal(0x00), buffer)
    if numchars ≢ nothing
        resize!(buffer, numchars - 1)
    end
    String(buffer)
end

"""
$(SIGNATURES)

Read length (of type T), then read and chomp the string.
"""
function readstrfs(boio::ByteOrderIO, T::Type{<:Integer})
    len = Int(readnum(boio, T))
    readchompedstring(boio, len)
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
        @assert verifytag(io -> readfixedstring(io, 3), io, "release") == "118"
        byteorder = readbyteorder(io)
        boio = ByteOrderIO(byteorder, io)
        K = verifytag(boio -> readnum(boio, Int16), boio, "K")
        N = verifytag(boio -> readnum(boio, Int64), boio, "N")
        label = verifytag(boio -> readstrfs(boio, Int16), boio, "label")
        timestamp = verifytag(boio -> readstrfs(boio, Int8), boio, "timestamp")
        DTAHeader(118, byteorder, Int(K), Int(N), label, timestamp), boio
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

function readmap(boio::ByteOrderIO)
    verifytag(boio, "map") do boio
        map = DTAMap([readnum(boio, Int64) for _ in 1:14]...)
        @assert map.stata_data_open == 0
        map
    end
end

const STRFSMAXLEN = 2045

struct StrFs{len}
    function StrFs{len}() where len
        @assert 1 ≤ len::Int ≤ STRFSMAXLEN
        new{len}()
    end
end

struct StrL end

function decode_variable_type(code::UInt16)
    if 1 ≤ code ≤ STRFSMAXLEN
        StrFs{Int(code)}
    elseif code == 32768
        StrL
    elseif 65526 ≤ code ≤ 65530
        (Float64, Float32, Int32, Int16, Int8)[code - 65525]
    else
        error("unrecognized variable type code $(code)")
    end
end

function read_variable_types(boio::ByteOrderIO, header::DTAHeader, map::DTAMap)
    seek(boio, map.variable_types)
    verifytag(boio, "variable_types") do boio
        ((decode_variable_type(readnum(boio, UInt16)) for _ in 1:header.variables)..., )
    end
end

function read_variable_names(boio::ByteOrderIO, header::DTAHeader, map::DTAMap)
    seek(boio, map.varnames)
    verifytag(boio, "varnames") do boio
        [readchompedstring(boio, 129) for _ in 1:header.variables]
    end
end

end # module
