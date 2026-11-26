"""Deterministic small ZIP corpus; no downloaded add-ons or user files."""
import pathlib
import stat
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)

def archive(name, entries, compression=zipfile.ZIP_DEFLATED):
    with zipfile.ZipFile(root / (name + '.zip'), 'w', compression=compression) as out:
        for path, data in entries:
            out.writestr(path, data)

toc = b'## Interface: 16001\n## Title: WolkaraForever Fixture\n## Version: 1\nmain.lua\n'
archive('valid', [('Fixture/', b''), ('Fixture/Fixture.toc', toc), ('Fixture/main.lua', b'-- fixture\n')])
archive('nested', [('Wrapper/Fixture/Fixture.toc', toc)])
for name, path in [('traversal', '../outside'), ('absolute', '/outside'), ('double', 'Fixture//file'),
                   ('dot', 'Fixture/./file'), ('colon', 'Fixture/a:b'), ('control', 'Fixture/a\nb')]:
    archive(name, [(path, b'bad')])
archive('case', [('Fixture/a', b'a'), ('Fixture/A', b'b')])
archive('unicode', [('Fixture/caf\u00e9', b'a'), ('Fixture/cafe\u0301', b'b')])
link = zipfile.ZipInfo('Fixture/link')
link.create_system = 3
link.external_attr = (stat.S_IFLNK | 0o777) << 16
archive('symlink', [(link, b'../../outside')])
archive('corrupt', [('Fixture/Fixture.toc', toc)], zipfile.ZIP_STORED)
path = root / 'corrupt.zip'
# Flip one byte of the stored entry's data: the archive stays structurally valid and
# the length is unchanged, so the CRC is the thing that must be refused. Replacing a
# word with a different-length one would shift every offset after it, which makes the
# fixture depend on the length of whatever text the entry happens to carry.
data = bytearray(path.read_bytes())
data[data.index(toc)] ^= 0xFF
path.write_bytes(data)
(root / 'invalid.zip').write_bytes(b'not a zip')
archive('file-directory', [('Fixture/a', b'file'), ('Fixture/a/b', b'child')])

archive('oversized-file', [('Fixture/large', b'0' * (64 * 1024 * 1024 + 1))])
archive('too-many', [(f'Fixture/{i}', b'') for i in range(20_001)])

# An entry whose mode says FIFO. ZIPFoundation cannot see it as anything but an ordinary
# file, so what must land on disk is a regular file with the entry's bytes in it - never a
# FIFO, which would block any later reader of that tree for ever. The test asserts that.
fifo = zipfile.ZipInfo('Fixture/fifo')
fifo.create_system = 3
fifo.external_attr = (stat.S_IFIFO | 0o644) << 16
archive('special-file', [('Fixture/Fixture.toc', toc), (fifo, b'not a fifo\n')])

# A deflate entry whose *declared* uncompressed size is a lie, which is the case the
# declared-size checks cannot catch: the compressed size is truthful, so the stream is read
# to its end and expands to 70 MiB while every declared-size check sees ten bytes. Built by
# rewriting the uncompressed-size field of the entry's central directory record (name length
# 2 + extra 2 + comment 2 + disk 2 + internal 2 + external 4 + offset 4 + crc 4 + compressed
# 4 = 24 bytes in).
archive('lying-size', [('Fixture/large', b'0' * (70 * 1024 * 1024))])
path = root / 'lying-size.zip'
data = bytearray(path.read_bytes())
central = data.find(b'PK\x01\x02')
assert central >= 0, 'the central directory record was not where it was expected'
data[central + 24:central + 28] = (10).to_bytes(4, 'little')
path.write_bytes(bytes(data))

# A package whose second folder's TOC is a baked database (QuestieDB's is 18 MB): the ## lines are at the
# top, the rest is data. The store reads only the head of a TOC, so the folder is still an add-on.
big_head = b'## Interface: 16001\n## Title: Big Pack DB\n## Version: 1\nDB.lua\n'
archive('big-toc', [('BigPack/BigPack.toc', b'## Interface: 16001\n## Title: Big Pack\n## Version: 1\nmain.lua\n'),
                    ('BigPack/main.lua', b'-- big pack\n'),
                    ('BigPackDB/BigPackDB.toc', big_head + b'## X-Baked: ' + b'7' * (3 * 1024 * 1024) + b'\n'),
                    ('BigPackDB/DB.lua', b'-- data\n')])
# A big TOC whose 256 KiB head ends inside a two-byte UTF-8 character: the head is cut back to its last
# whole line, so the title is read as UTF-8 rather than as Latin-1.
utf8_head = '## Interface: 16001\n## Title: Caf\u00e9 Data\n## Version: 1\n'.encode()
pad = (256 * 1024 - 1 - len(utf8_head)) % 2
utf8_toc = utf8_head + b'x' * pad + '\u00e9'.encode() * 200_000 + b'\n'
assert utf8_toc[256 * 1024 - 1] == 0xC3, 'the head must end on the first byte of a two-byte character'
archive('big-toc-utf8', [('Utf8Data/Utf8Data.toc', utf8_toc)])
