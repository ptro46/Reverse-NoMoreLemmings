"""Decode the backwards ByteKiller stream used by this Amiga disk."""
import struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def unpack(data):
    size=int.from_bytes(data[-4:],'big')
    if not 0<size<2_000_000: raise ValueError('Invalid output length')
    pos=len(data)-12
    bits=int.from_bytes(data[pos:pos+4],'big')
    checksum=int.from_bytes(data[-8:-4],'big')^bits
    out=bytearray(size); cursor=size
    def bit():
        nonlocal bits,pos,checksum
        value=bits&1; bits>>=1
        if bits==0:
            pos-=4
            if pos<0: raise ValueError('Input exhausted')
            word=int.from_bytes(data[pos:pos+4],'big'); checksum^=word
            value=word&1; bits=(word>>1)|0x80000000
        return value
    def read(n):
        value=0
        for _ in range(n): value=(value<<1)|bit()
        return value
    while cursor:
        if bit()==0:
            if bit()==0: count=read(3)+1; distance=None
            else: count=2; distance=read(8)
        else:
            code=read(2)
            if code==3: count=read(8)+9; distance=None
            elif code==2: count=read(8)+1; distance=read(12)
            else: count=code+3; distance=read(code+9)
        if count>cursor: raise ValueError('Output overrun')
        for _ in range(count):
            cursor-=1
            if distance is None: out[cursor]=read(8)
            else:
                if not distance or cursor+distance>=size: raise ValueError('Invalid match')
                out[cursor]=out[cursor+distance]
    if checksum: raise ValueError(f'Checksum mismatch: {checksum:08x}')
    return bytes(out)

if __name__=='__main__':
    dest=ROOT/'Assets'/'decoded';dest.mkdir(exist_ok=True)
    for p in sorted((ROOT/'Assets'/'raw').iterdir()):
        if p.name in ('Code','leveldata') or p.name.startswith(('Level','Ground','Objects','tune')):
            try:
                data=unpack(p.read_bytes());(dest/p.name).write_bytes(data)
                print(p.name,len(p.read_bytes()),'->',len(data),repr(data[:24]))
            except Exception as e: print(p.name,'ERROR',e)
