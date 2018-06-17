# Check for an iconv implementation with the GNU (non-POSIX) behavior:
# EILSEQ is returned when a sequence cannot be converted to target encoding,
# instead of succeeding and only returning the number of invalid conversions
# This non-standard behavior is required to allow replacing invalid sequences
# with a user-defined character.
# Implementations with this behavior include glibc, GNU libiconv (on which Mac
# OS X's is based) and win_iconv.
function validate_iconv(lib, iconv_open, iconv_close, iconv)
    h = Libdl.dlopen_e(lib)
    h == C_NULL && return false
    # Needed to check libc
    f = Libdl.dlsym_e(h, iconv_open)
    f == C_NULL && return false

    cd = ccall(f, Ptr{Void}, (Cstring, Cstring), "ASCII", "UTF-8")
    cd == Ptr{Void}(-1) && return false

    s = "café"
    a = Vector{UInt8}(sizeof(s))
    inbufptr = Ref{Ptr{UInt8}}(pointer(s))
    inbytesleft = Ref{Csize_t}(sizeof(s))
    outbufptr = Ref{Ptr{UInt8}}(pointer(a))
    outbytesleft = Ref{Csize_t}(length(a))
    ret = ccall(Libdl.dlsym_e(h, iconv), Csize_t,
                (Ptr{Void}, Ptr{Ptr{UInt8}}, Ref{Csize_t}, Ptr{Ptr{UInt8}}, Ref{Csize_t}),
                cd, inbufptr, inbytesleft, outbufptr, outbytesleft)
    ccall(Libdl.dlsym_e(h, iconv_close), Void, (Ptr{Void},), cd) == -1 && return false

    return ret == -1 % Csize_t && Libc.errno() == Libc.EILSEQ
end

using BinaryProvider

# Parse some basic command-line arguments
const verbose = "--verbose" in ARGS
const prefix = Prefix(get([a for a in ARGS if a != "--verbose"], 1, joinpath(@__DIR__, "usr")))
products = [
    LibraryProduct(prefix, String["libiconv"], :libiconv)
]

# Download binaries from hosted location
bin_prefix = "https://github.com/JuliaStrings/IConvBuilder/releases/download/v1.15+build.2"

# Listing of files generated by BinaryBuilder:
download_info = Dict(
    BinaryProvider.Linux(:aarch64, :glibc, :blank_abi) => ("$bin_prefix/IConv.aarch64-linux-gnu.tar.gz", "3e6a353988e5089c7b49fb79350d90c31475c10c3d7c1271f889889db53d307f"),
    BinaryProvider.Linux(:aarch64, :musl, :blank_abi) => ("$bin_prefix/IConv.aarch64-linux-musl.tar.gz", "2dc859f220a7df89b68e31a1e772a461e288e5b4691ccb2fc76ec0b1e828b98a"),
    BinaryProvider.Linux(:armv7l, :glibc, :eabihf) => ("$bin_prefix/IConv.arm-linux-gnueabihf.tar.gz", "43900a0baaaf7b43f8c67ec022bb488cae4972acb958562cfc533294a3acf93e"),
    BinaryProvider.Linux(:armv7l, :musl, :eabihf) => ("$bin_prefix/IConv.arm-linux-musleabihf.tar.gz", "2547a615f078af1a877447a06717337bf1588bc7e81d19163b73905902681fe0"),
    BinaryProvider.Linux(:i686, :glibc, :blank_abi) => ("$bin_prefix/IConv.i686-linux-gnu.tar.gz", "b7af0081f0d0f5be0020053d811d7dc2d2f1d0349009a0258c19319a2835c490"),
    BinaryProvider.Linux(:i686, :musl, :blank_abi) => ("$bin_prefix/IConv.i686-linux-musl.tar.gz", "a3e6869733ec511e2e45347607515cdf05b92b48dfbd5c3cb5e47bdf78cfe4cd"),
    BinaryProvider.Windows(:i686, :blank_libc, :blank_abi) => ("$bin_prefix/IConv.i686-w64-mingw32.tar.gz", "247cc617fbc0e059943d905e068171479e1a354c6b59b8a298bfda98ec0230f5"),
    BinaryProvider.Linux(:powerpc64le, :glibc, :blank_abi) => ("$bin_prefix/IConv.powerpc64le-linux-gnu.tar.gz", "62bee599a09dfb98e0d410fd93d30188cb0472295f25b9cc05e31dda35904ab8"),
    BinaryProvider.MacOS(:x86_64, :blank_libc, :blank_abi) => ("$bin_prefix/IConv.x86_64-apple-darwin14.tar.gz", "1489b867362c1ee6daa8e16361daa7f9d9613a67cb684d1eb8b93b3d74137188"),
    BinaryProvider.Linux(:x86_64, :glibc, :blank_abi) => ("$bin_prefix/IConv.x86_64-linux-gnu.tar.gz", "a61ec482c81bca8c1fb3108908481c14d61668fa11b5ef0498badad2119559e5"),
    BinaryProvider.Linux(:x86_64, :musl, :blank_abi) => ("$bin_prefix/IConv.x86_64-linux-musl.tar.gz", "75d2b2e02e0ca3cb6efe38be071556d222c7d5a0755c077717eea6391870832f"),
    BinaryProvider.FreeBSD(:x86_64, :blank_libc, :blank_abi) => ("$bin_prefix/IConv.x86_64-unknown-freebsd11.1.tar.gz", "144e7e0f6d66178e357f5279a04a92b4aa50051a6061f0eec06045d63dd283f4"),
    BinaryProvider.Windows(:x86_64, :blank_libc, :blank_abi) => ("$bin_prefix/IConv.x86_64-w64-mingw32.tar.gz", "e7840895294b82bbacbf1002aa6b3a739b68de31e119c177126a6da5fe7ff227"),
)

# Detect already present libc iconv or libiconv
# (notably for Linux, Mac OS and other Unixes)
found_iconv = false
for lib in ("libc", "libc-bin", "libiconv", "iconv")
    if lib in ("libc", "libc-bin")
        global iconv_open = :iconv_open
        global iconv_close = :iconv_close
        global iconv = :iconv
    else
        global iconv_open =  :libiconv_open
        global iconv_close = :libiconv_close
        global iconv = :libiconv
    end
    if validate_iconv(lib, iconv_open, iconv_close, iconv)
        found_iconv = true
        write(joinpath(@__DIR__, "deps.jl"),
              """
              ## This file autogenerated by Pkg.build(\\"StringEncodings\\").
              ## Do not edit.
              const libiconv = "$lib"
              function check_deps()
                  global libiconv
                  if Libdl.dlopen_e(libiconv) == C_NULL
                      error("\$(libiconv) cannot be opened. Please re-run Pkg.build(\\"StringEncodings\\"), and restart Julia.")
                  end

              end
              """)
        break
    end
end

if !found_iconv
    iconv_open =  :libiconv_open
    iconv_close = :libiconv_close
    iconv = :libiconv
    # Install unsatisfied or updated dependencies:
    unsatisfied = any(!satisfied(p; verbose=verbose) for p in products)
    if haskey(download_info, platform_key())
        url, tarball_hash = download_info[platform_key()]
        if unsatisfied || !isinstalled(url, tarball_hash; prefix=prefix)
            # Download and install binaries
            install(url, tarball_hash; prefix=prefix, force=true, verbose=verbose)
        end
    elseif unsatisfied
        # If we don't have a BinaryProvider-compatible .tar.gz to download, complain.
        # Alternatively, you could attempt to install from a separate provider,
        # build from source or something even more ambitious here.
        error("Your platform $(triplet(platform_key())) is not supported by this package! Try installing libiconv manually.")
    end

    # Write out a deps.jl file that will contain mappings for our products
    write_deps_file(joinpath(@__DIR__, "deps.jl"), products)
end

open(joinpath(@__DIR__, "deps.jl"), "a") do io
    write(io,
          """
          const iconv_open_s = :$iconv_open
          const iconv_close_s = :$iconv_close
          const iconv_s = :$iconv
          """)
end