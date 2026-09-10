#!/usr/bin/env python3
# Select an English keyboard layout via Carbon TISSelectInputSource.
# Prefers ABC, then US, then any enabled keyboard layout (not an IME).
import ctypes
import ctypes.util
import sys

kCFStringEncodingUTF8 = 0x08000100


def _lib(name):
    path = ctypes.util.find_library(name)
    if not path:
        raise OSError('missing %s' % name)
    return ctypes.cdll.LoadLibrary(path)


def main():
    carbon = _lib('Carbon')
    cf = _lib('CoreFoundation')

    cf.CFStringCreateWithCString.restype = ctypes.c_void_p
    cf.CFStringCreateWithCString.argtypes = [
        ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
    cf.CFStringGetCString.restype = ctypes.c_bool
    cf.CFStringGetCString.argtypes = [
        ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
    cf.CFStringGetLength.restype = ctypes.c_long
    cf.CFStringGetLength.argtypes = [ctypes.c_void_p]
    cf.CFStringGetMaximumSizeForEncoding.restype = ctypes.c_long
    cf.CFStringGetMaximumSizeForEncoding.argtypes = [
        ctypes.c_long, ctypes.c_uint32]
    cf.CFArrayGetCount.restype = ctypes.c_long
    cf.CFArrayGetCount.argtypes = [ctypes.c_void_p]
    cf.CFArrayGetValueAtIndex.restype = ctypes.c_void_p
    cf.CFArrayGetValueAtIndex.argtypes = [ctypes.c_void_p, ctypes.c_long]
    cf.CFDictionaryCreate.restype = ctypes.c_void_p
    cf.CFDictionaryCreate.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_void_p),
        ctypes.POINTER(ctypes.c_void_p),
        ctypes.c_long,
        ctypes.c_void_p,
        ctypes.c_void_p,
    ]

    key_cb = ctypes.c_void_p.in_dll(cf, 'kCFTypeDictionaryKeyCallBacks')
    val_cb = ctypes.c_void_p.in_dll(cf, 'kCFTypeDictionaryValueCallBacks')
    prop_id = ctypes.c_void_p.in_dll(carbon, 'kTISPropertyInputSourceID')
    prop_type = ctypes.c_void_p.in_dll(carbon, 'kTISPropertyInputSourceType')

    carbon.TISCreateInputSourceList.restype = ctypes.c_void_p
    carbon.TISCreateInputSourceList.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    carbon.TISGetInputSourceProperty.restype = ctypes.c_void_p
    carbon.TISGetInputSourceProperty.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    carbon.TISSelectInputSource.restype = ctypes.c_int32
    carbon.TISSelectInputSource.argtypes = [ctypes.c_void_p]

    def cfstr(s):
        return cf.CFStringCreateWithCString(None, s.encode('utf-8'), kCFStringEncodingUTF8)

    def pystr(ref):
        if not ref:
            return None
        n = cf.CFStringGetLength(ref)
        size = cf.CFStringGetMaximumSizeForEncoding(n, kCFStringEncodingUTF8) + 1
        buf = ctypes.create_string_buffer(size)
        if not cf.CFStringGetCString(ref, buf, size, kCFStringEncodingUTF8):
            return None
        return buf.value.decode('utf-8')

    def select_id(ident):
        ident_cf = cfstr(ident)
        keys = (ctypes.c_void_p * 1)(prop_id)
        vals = (ctypes.c_void_p * 1)(ident_cf)
        filt = cf.CFDictionaryCreate(None, keys, vals, 1, key_cb, val_cb)
        lst = carbon.TISCreateInputSourceList(filt, 0)
        if not lst or cf.CFArrayGetCount(lst) < 1:
            return False
        src = cf.CFArrayGetValueAtIndex(lst, 0)
        return carbon.TISSelectInputSource(src) == 0

    for ident in ('com.apple.keylayout.ABC', 'com.apple.keylayout.US'):
        if select_id(ident):
            return 0

    lst = carbon.TISCreateInputSourceList(None, 0)
    if not lst:
        return 1
    n = cf.CFArrayGetCount(lst)
    for i in range(n):
        src = cf.CFArrayGetValueAtIndex(lst, i)
        kind = pystr(carbon.TISGetInputSourceProperty(src, prop_type))
        if kind != 'TISTypeKeyboardLayout':
            continue
        if carbon.TISSelectInputSource(src) == 0:
            return 0
    return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        sys.exit(1)
