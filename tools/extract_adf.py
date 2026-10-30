#!/usr/bin/env python3
"""Extract the custom file table of the supplied Lemmings ADF and decode IFF assets.
Python 3 standard library only. Does not modify the source disk.
"""
import argparse, hashlib, json, re, struct, wave, zlib
from pathlib import Path


def chunks(data):
    end = struct.unpack_from('>I', data, 4)[0] + 8
    if end > len(data):
        raise ValueError('Truncated FORM')
    pos = 12
    result = {}
    while pos + 8 <= end:
        tag, size = struct.unpack_from('>4sI', data, pos)
        if pos + 8 + size > end:
            raise ValueError('Truncated IFF chunk')
        result[tag] = data[pos+8:pos+8+size]
        pos += 8 + size + (size & 1)
    return result


def byterun(data, expected):
    out = bytearray(); pos = 0
    while len(out) < expected and pos < len(data):
        count = data[pos]; pos += 1
        if count <= 127:
            out.extend(data[pos:pos+count+1]); pos += count+1
        elif count >= 129:
            out.extend(data[pos:pos+1] * (257-count)); pos += 1
    if len(out) != expected:
        raise ValueError('Unexpected ByteRun size')
    return out


def png_image(data, target):
    c = chunks(data)
    w,h,x,y,planes,mask,compression,pad,transparent,xa,ya,pw,ph = struct.unpack('>HHhhBBBBHBBhh',c[b'BMHD'])
    if planes > 8 or compression not in (0,1) or mask not in (0,1,2):
        raise ValueError('Unsupported ILBM mode')
    camg = int.from_bytes(c.get(b'CAMG',b'\0'*4),'big')
    if camg & 0x800:
        raise ValueError('HAM mode needs separate decoder')
    row = ((w+15)//16)*2; stored = planes+(mask==1)
    expected = row*h*stored
    raw = byterun(c[b'BODY'],expected) if compression else c[b'BODY']
    if len(raw)!=expected: raise ValueError('Invalid bitmap size')
    palette = [tuple(c[b'CMAP'][i:i+3]) for i in range(0,len(c[b'CMAP']),3)]
    if camg & 0x80:
        palette = palette[:32]+[tuple(v//2 for v in rgb) for rgb in palette[:32]]
    pixels = bytearray()
    for yy in range(h):
        pixels.append(0)
        base=yy*row*stored
        for xx in range(w):
            bit=7-xx%8
            index=sum(((raw[base+p*row+xx//8]>>bit)&1)<<p for p in range(planes))
            alpha=255
            if mask==1: alpha=255*((raw[base+planes*row+xx//8]>>bit)&1)
            elif mask==2 and index==transparent: alpha=0
            pixels.extend((*palette[index],alpha))
    def chunk(tag,body):
        return struct.pack('>I',len(body))+tag+body+struct.pack('>I',zlib.crc32(tag+body)&0xffffffff)
    target.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b''))
    return {'width':w,'height':h,'planes':planes}


def wav_audio(data,target):
    c=chunks(data)
    one,repeat,cycle,rate,octaves,compression,volume=struct.unpack('>IIIHBBI',c[b'VHDR'])
    if compression or octaves!=1 or b'CHAN' in c and int.from_bytes(c[b'CHAN'],'big')==6:
        raise ValueError('Compressed, multi-octave or stereo sound needs separate decoder')
    samples=bytes(v^128 for v in c[b'BODY'])
    with wave.open(str(target),'wb') as f:
        f.setnchannels(1); f.setsampwidth(1); f.setframerate(rate); f.writeframes(samples)
    return {'sample_rate':rate,'samples':len(samples),'duration_seconds':round(len(samples)/rate,3),'loop_start':one,'loop_length':repeat}


def extract(source,out):
    data=source.read_bytes(); out.mkdir(parents=True,exist_ok=True)
    for folder in ('raw','images','audio'): (out/folder).mkdir(exist_ok=True)
    entries=[]; offset=0
    for pos in range(0x400,0x1000,16):
        entry=data[pos:pos+16]; name=entry[:12].split(b'\0')[0]
        if not re.fullmatch(rb'[A-Za-z0-9_]+',name): break
        size=struct.unpack_from('>I',entry,12)[0]
        if not size or offset+size>len(data): raise ValueError('Invalid custom file table')
        name=name.decode(); payload=data[offset:offset+size]
        (out/'raw'/name).write_bytes(payload)
        record={'name':name,'offset':offset,'size':size,'sha256':hashlib.sha256(payload).hexdigest(),'conversions':[]}
        # Some named resources contain several concatenated IFF files.
        for match in re.finditer(b'FORM',payload):
            start=match.start()
            if start+12>len(payload): continue
            kind=payload[start+8:start+12]
            if kind not in (b'ILBM',b'8SVX'): continue
            length=struct.unpack_from('>I',payload,start+4)[0]+8
            form=payload[start:start+length]
            label=name+(f'_{start:05x}' if start else '')
            try:
                if kind==b'ILBM':
                    dest=Path('images')/(label+'.png'); meta=png_image(form,out/dest)
                else:
                    dest=Path('audio')/(label+'.wav'); meta=wav_audio(form,out/dest)
                record['conversions'].append({'path':str(dest),**meta})
            except (ValueError,KeyError,IndexError,struct.error) as error:
                record['conversions'].append({'offset':start,'error':str(error)})
        entries.append(record); offset+=size
    report={'source':str(source),'source_sha256':hashlib.sha256(data).hexdigest(),'file_count':len(entries),'files':entries}
    (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"{len(entries)} resources extracted; {len(list((out/'images').glob('*.png')))} PNG; {len(list((out/'audio').glob('*.wav')))} WAV")
    for e in entries:
        for c in e['conversions']:
            if 'error' in c: print(e['name'],c)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('adf',type=Path); parser.add_argument('output',type=Path)
    args=parser.parse_args(); extract(args.adf,args.output)
