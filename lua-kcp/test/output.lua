
function pack_output(subid, buf)
    print("pack_output =", subid, buf)
    return string.pack(">I4s2", subid, buf)
end

function unpack_output(msg)
    print("unpack_output msg=", msg)
    local subid, buf = string.unpack(">I4s2", msg)
    print("unpack_output subid=", subid, "buf=", buf)
    return subid, buf
end