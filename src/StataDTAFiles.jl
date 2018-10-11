module StataDTAFiles

using ArgCheck: @argcheck
using DocStringExtensions: SIGNATURES
using Parameters: @unpack
using StrFs: StrF

import Base: read, seek, iterate, length, open, close, eltype, show

export DTAFile, StrFs, StrL, dtatypes, vartypes


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

function verifytag(f::Function, io::IO, tag)
    verifytag(io, tag)
    result = f(io)
    verifytag(io, tag, true)
    result
end


# reading primitives

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

"""
Number types is Stata that correspond to native Julia types, and are denoted by the latter.
"""
const DATANUMTYPES = Union{Int8, Int16, Int32, Float32, Float64}

"""
Number types which are read by `readnum`, in addition to `DATANUMTYPES`.
"""
const EXTRANUMTYPES = Union{Int64, UInt8, UInt16, UInt32, UInt64}

"""
All number types read by `readnum`.
"""
const READNUMTYPES = Union{DATANUMTYPES, EXTRANUMTYPES}

readnum(boio::ByteOrderIO{MSF}, T::Type{<:READNUMTYPES}) = ntoh(read(boio.io, T))

readnum(boio::ByteOrderIO{LSF}, T::Type{<:READNUMTYPES}) = ltoh(read(boio.io, T))

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
function readchompedstring(boio::ByteOrderIO, T::Type{<:Integer})
    len = Int(readnum(boio, T))
    readchompedstring(boio, len)
end


# header

"""
DTA file header (without the byte order, which is encoded in the corresponding `ByteOrderIO`.
"""
struct DTAHeader
    release::Int
    variables::Int
    observations::Int
    label::String
    timestamp::String           # FIXME parse date in timestamp
end

function read_header(io::IO)
    verifytag(io, "header") do io
        @assert verifytag(io -> readfixedstring(io, 3), io, "release") == "118"
        byteorder = readbyteorder(io)
        boio = ByteOrderIO(byteorder, io)
        K = verifytag(boio -> readnum(boio, Int16), boio, "K")
        N = verifytag(boio -> readnum(boio, Int64), boio, "N")
        label = verifytag(boio -> readchompedstring(boio, Int16), boio, "label")
        timestamp = verifytag(boio -> readchompedstring(boio, Int8), boio, "timestamp")
        DTAHeader(118, Int(K), Int(N), label, timestamp), boio
    end
end


# map

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

function read_map(boio::ByteOrderIO)
    verifytag(boio, "map") do boio
        map = DTAMap([readnum(boio, Int64) for _ in 1:14]...)
        @assert map.stata_data_open == 0
        map
    end
end


# types

"""
Maximum length of `str#` (aka `strfs`) strings in Stata DTA files.
"""
const STRFSMAXLEN = 2045

function decode_variable_type(code::UInt16)
    if 1 ≤ code ≤ STRFSMAXLEN
        StrF{Int(code)}
    elseif code == 32768
        String
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

vartype(::Type{T}) where {T <: DATANUMTYPES} = Union{Missing, T}

vartype(::Type{T}) where {T <: Union{StrF, String}} = T


# metadata

function read_variable_names(boio::ByteOrderIO, header::DTAHeader, map::DTAMap)
    seek(boio, map.varnames)
    verifytag(boio, "varnames") do boio
        ntuple(_ -> Symbol(readchompedstring(boio, 129)), header.variables)
    end
end

function read_sortlist(boio::ByteOrderIO, header::DTAHeader, map::DTAMap)
    seek(boio, map.sortlist)
    verifytag(boio, "sortlist") do boio
        sortlist = [readnum(boio, Int16) for _ in 1:(header.variables + 1)]
        terminator = findfirst(iszero, sortlist)
        @assert terminator ≢ nothing
        sortlist[1:(terminator-1)]
    end
end

function read_formats(boio::ByteOrderIO, header::DTAHeader, map::DTAMap)
    seek(boio, map.formats)
    verifytag(boio, "formats") do boio
        [readchompedstring(boio, 57) for _ in 1:header.variables]
    end
end


# read data

const MAXINT8 = Int8(0x64)
const MAXINT16 = Int16(0x7fe4)
const MAXINT32 = Int32(0x7fffffe5)
const MAXFLOAT32 = Float32(0x1.fffffep126)
const MAXFLOAT64 = Float64(0x1.fffffffffffffp1022)

decode_missing(x::Int8) = x ≥ MAXINT8 ? missing : x
decode_missing(x::Int16) = x ≥ MAXINT16 ? missing : x
decode_missing(x::Int32) = x ≥ MAXINT32 ? missing : x
decode_missing(x::Float32) = x ≥ MAXFLOAT32 ? missing : x
decode_missing(x::Float64) = x ≥ MAXFLOAT64 ? missing : x

readfield(boio::ByteOrderIO, T::Type{<: DATANUMTYPES}) = decode_missing(read(boio, T))

readfield(boio::ByteOrderIO, ::Type{StrF{N}}) where N = read(boio, StrF{N})

readrow(boio::ByteOrderIO, vartypes) = map(T -> readfield(boio, T), vartypes)


#

struct DTAFile{VT, B <: ByteOrderIO, VN}
    boio::B
    header::DTAHeader
    map::DTAMap
    variable_names::VN
    sortlist::Vector{Int16}
    formats::Vector{String}
end

function show(io::IO, dta::DTAFile)
    @unpack header, variable_names, sortlist, formats = dta
    @unpack release, variables, observations, label, timestamp = header
    COLORHEADER = :red
    COLORVAR = :blue
    COLORTYPE = :green
    print(io, "Stata DTA file $(release), ")
    printstyled(io, "$(variables) vars in $(observations) rows"; color = COLORHEADER)
    println(io, ", ", strip(timestamp))
    isempty(label) || println(io, "    label: ", label)
    if isempty(sortlist)
        println(io, "    not sorted")
    else
        print(io, "    sorted by ")
        printstyled(io, variable_names[sortlist], "\n"; color = COLORVAR)
    end
    for (i, (variable_name, dtatype, format)) in enumerate(zip(variable_names, dtatypes(dta), formats))
        i == 1 || println(io)
        print(io, "  ")
        printstyled(io, variable_name; color = COLORVAR)
        print(io, "::")
        printstyled(io, dtatype; color = COLORTYPE)
        print(io, " [", format, "]")
    end
end

open(::Type{DTAFile}, path::AbstractString) = open(DTAFile, open(path, "r"))

function open(::Type{DTAFile}, io::IO)
    seekstart(io)
    verifytag(io, "stata_dta")
    # read header and map
    header, boio = read_header(io)
    map = read_map(boio)
    # read the rest using map
    variable_names = read_variable_names(boio, header, map)
    sortlist = read_sortlist(boio, header, map)
    formats = read_formats(boio, header, map)
    variable_types = read_variable_types(boio, header, map)
    DTAFile{Tuple{variable_types...}, typeof(boio), typeof(variable_names)
            }(boio, header, map, variable_names, sortlist, formats)
end

function open(f::Function, ::Type{DTAFile}, args...)
    dta = open(DTAFile, args...)
    try
        f(dta)
    finally
        close(dta)
    end
end

close(dta::DTAFile) = close(dta.boio.io)

dtatypes(dta::DTAFile{VT}) where VT = ntuple(i -> fieldtype(VT, i), fieldcount(VT))

vartypes(dta::DTAFile) = vartype.(dtatypes(dta))


# iteration interface

eltype(dta::DTAFile) = Tuple{vartypes(dta)...}
length(dta::DTAFile) = dta.header.observations

function iterate(dta::DTAFile, index = 1)
    @unpack boio = dta
    if index > dta.header.observations
        nothing
    else
        if index == 1
            seek(boio, dta.map.data)
            verifytag(boio, "data")
        end
        readrow(boio, dtatypes(dta)), index + 1
    end
end

end # module
