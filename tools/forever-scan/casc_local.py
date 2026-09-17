"""Read files out of a local WoW install's CASC storage, by FileDataID, with nothing but Python.

    python casc_local.py <wow-dir> <product> <fdid> [<fdid> ...] [--out <dir>]
    python casc_local.py "E:/World of Warcraft" wow_classic_beta 4637043 --out /tmp/local

Used by the Forever scan to check what wago.tools serves against the build actually installed.
Encrypted blocks (BLTE mode E) are reported, not decrypted.
"""
import glob
import os
import struct
import sys
import zlib

LOCALE_ENUS = 0x2
NO_NAME_HASH = 0x10000000


class Encrypted(Exception):
    pass


def read_build_info(wow_dir, product):
    lines = open(os.path.join(wow_dir, ".build.info"), encoding="utf-8").read().splitlines()
    head = [h.split("!")[0] for h in lines[0].split("|")]
    for line in lines[1:]:
        row = dict(zip(head, line.split("|")))
        if row.get("Product") == product:
            return row
    raise KeyError(product)


def read_config(data_dir, key):
    path = os.path.join(data_dir, "config", key[0:2], key[2:4], key)
    out = {}
    for line in open(path, encoding="utf-8"):
        if " = " in line:
            k, v = line.rstrip("\n").split(" = ", 1)
            out[k] = v.split()
    return out


def load_indices(data_dir):
    """EKey (first 9 bytes) -> (archive number, offset, size), from the newest .idx of each bucket."""
    newest = {}
    for path in glob.glob(os.path.join(data_dir, "data", "*.idx")):
        name = os.path.basename(path)[:-4]
        bucket, version = name[:2], int(name[2:], 16)
        if bucket not in newest or version > newest[bucket][0]:
            newest[bucket] = (version, path)
    index = {}
    for _, path in newest.values():
        raw = open(path, "rb").read()
        header_size = struct.unpack_from("<I", raw, 0)[0]
        pos = 8 + header_size
        pos = (pos + 15) & ~15  # the entries block starts on a 16-byte boundary
        entries_size = struct.unpack_from("<I", raw, pos)[0]
        pos += 8
        for off in range(pos, pos + entries_size, 18):
            ekey = raw[off:off + 9]
            packed = int.from_bytes(raw[off + 9:off + 14], "big")
            size = struct.unpack_from("<I", raw, off + 14)[0]
            index.setdefault(ekey, (packed >> 30, packed & 0x3FFFFFFF, size))
    return index


def blte(data):
    if data[:4] != b"BLTE":
        raise ValueError("not BLTE")
    header_size = struct.unpack_from(">I", data, 4)[0]
    if header_size == 0:
        chunks = [data[8:]]
    else:
        count = int.from_bytes(data[9:12], "big")
        pos, chunks, body = 12, [], header_size
        for _ in range(count):
            csize = struct.unpack_from(">I", data, pos)[0]
            chunks.append(data[body:body + csize])
            body += csize
            pos += 24
    out = bytearray()
    for chunk in chunks:
        mode, payload = chunk[:1], chunk[1:]
        if mode == b"N":
            out += payload
        elif mode == b"Z":
            out += zlib.decompress(payload)
        elif mode == b"F":
            out += blte(payload)
        elif mode == b"E":
            raise Encrypted()
        else:
            raise ValueError(f"BLTE mode {mode!r}")
    return bytes(out)


class Storage:
    def __init__(self, wow_dir, product):
        self.data_dir = os.path.join(wow_dir, "Data")
        info = read_build_info(wow_dir, product)
        self.build = read_config(self.data_dir, info["Build Key"])
        self.index = load_indices(self.data_dir)
        self._archives = {}
        self.encoding = self._parse_encoding(self.read_ekey(bytes.fromhex(self.build["encoding"][1])))
        self.root = self._parse_root(self.read_ckey(bytes.fromhex(self.build["root"][0])))

    def read_ekey(self, ekey):
        hit = self.index.get(ekey[:9])
        if not hit:
            raise KeyError(ekey.hex())
        archive, offset, size = hit
        f = self._archives.get(archive)
        if f is None:
            f = self._archives[archive] = open(os.path.join(self.data_dir, "data", f"data.{archive:03d}"), "rb")
        f.seek(offset + 30)  # each stored blob carries a 30-byte header before its BLTE
        return blte(f.read(size - 30))

    def read_ckey(self, ckey):
        return self.read_ekey(self.encoding[ckey])

    def read_fdid(self, fdid):
        return self.read_ckey(self.root[fdid])

    @staticmethod
    def _parse_encoding(raw):
        assert raw[:2] == b"EN", raw[:2]
        ckey_size, ekey_size = raw[3], raw[4]
        ce_page_kb = struct.unpack_from(">H", raw, 5)[0]
        ce_pages = struct.unpack_from(">I", raw, 9)[0]
        espec_size = struct.unpack_from(">I", raw, 18)[0]
        pos = 22 + espec_size + ce_pages * (ckey_size + 16)
        page_size = ce_page_kb * 1024
        table = {}
        for p in range(ce_pages):
            page = pos + p * page_size
            off, end = page, page + page_size
            while off + 6 + ckey_size <= end:
                count = raw[off]
                if count == 0:
                    break
                ckey = raw[off + 6:off + 6 + ckey_size]
                table[ckey] = raw[off + 6 + ckey_size:off + 6 + ckey_size + ekey_size]
                off += 6 + ckey_size + ekey_size * count
        return table

    @staticmethod
    def _parse_root(raw):
        assert raw[:4] == b"TSFM", raw[:4]
        a, b = struct.unpack_from("<II", raw, 4)
        if a == 0x18 and b in (1, 2):
            version, pos = b, 4 + 4 + 4 + 4 + 4 + 4
        else:
            version, pos = 0, 12
        roots = {}
        while pos < len(raw):
            if version >= 2:
                count, locale, flags1, flags2 = struct.unpack_from("<IIII", raw, pos)
                flags3 = raw[pos + 16]
                content = flags1 | flags2 | (flags3 << 17)
                pos += 17
            else:
                count, content, locale = struct.unpack_from("<III", raw, pos)
                pos += 12
            deltas = struct.unpack_from(f"<{count}i", raw, pos)
            pos += 4 * count
            ckeys = pos
            pos += 16 * count
            if not content & NO_NAME_HASH:
                pos += 8 * count
            wanted = locale & LOCALE_ENUS or locale == 0xFFFFFFFF
            fdid = -1
            for i, delta in enumerate(deltas):
                fdid += delta + 1
                if wanted and fdid not in roots:
                    roots[fdid] = raw[ckeys + 16 * i:ckeys + 16 * i + 16]
        return roots


def main():
    args = sys.argv[1:]
    out = None
    if "--out" in args:
        i = args.index("--out")
        out = args[i + 1]
        args = args[:i] + args[i + 2:]
    wow_dir, product, fdids = args[0], args[1], [int(x) for x in args[2:]]
    storage = Storage(wow_dir, product)
    print(f"{product}: {storage.build.get('build-name', ['?'])[0]}; root {len(storage.root)} files, "
          f"encoding {len(storage.encoding)} keys, index {len(storage.index)} blobs")
    for fdid in fdids:
        try:
            data = storage.read_fdid(fdid)
        except Encrypted:
            print(f"{fdid}: encrypted")
            continue
        except KeyError as e:
            print(f"{fdid}: not in this build ({e})")
            continue
        print(f"{fdid}: {len(data)} bytes")
        if out:
            os.makedirs(out, exist_ok=True)
            open(os.path.join(out, str(fdid)), "wb").write(data)


if __name__ == "__main__":
    main()
