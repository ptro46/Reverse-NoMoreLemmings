"""Convert original Amiga graphics, descriptors and levels to native engine assets."""
from pathlib import Path
import struct,json
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]; A=ROOT/'Assets'; OUT=A/'game'; OUT.mkdir(exist_ok=True)
meta=(A/'decoded/leveldata').read_bytes(); code=(A/'decoded/Code').read_bytes()
def u16(b,o): return struct.unpack_from('>H',b,o)[0]
def s16(b,o): return struct.unpack_from('>h',b,o)[0]
def rgb(v): return ((v>>8&15)*17,(v>>4&15)*17,(v&15)*17)
def planar(b,off,w,h,planes,palette,mask=None,base=0):
    row=w//8; plane=row*h
    assert off>=0 and off+planes*plane<=len(b),(off,w,h,planes,len(b))
    im=Image.new('RGBA',(w,h)); pix=im.load()
    for y in range(h):
        for x in range(w):
            i=y*row+x//8; shift=7-x%8
            v=sum(((b[off+p*plane+i]>>shift)&1)<<p for p in range(planes))
            alpha=((b[mask+i]>>shift)&1) if mask is not None else bool(v)
            pix[x,y]=(*palette[v|base],255 if alpha else 0)
    return im
styles=[]
for style in range(4):
    m=meta[style*0x590:(style+1)*0x590]; pal=[rgb(u16(m,i*2)) for i in range(16)]
    ground=(A/f'decoded/Ground{style+1}').read_bytes(); objects=(A/f'decoded/Objects{style+1}').read_bytes()
    folder=OUT/f'style{style}';folder.mkdir(exist_ok=True); tiles=[]; obs=[]
    for i in range(64):
        w,h,src,mask=struct.unpack_from('>HHII',m,0x290+i*12)
        if w==65535 or not w or not h: tiles.append(None);continue
        im=planar(ground,src-0x75578,w,h,3,pal,mask-0x75578,8)
        name=f'style{style}/terrain{i}.png'; im.save(OUT/name); tiles.append({'image':name,'width':w,'height':h})
    for i in range(17):
        o=0x70+i*34; words=struct.unpack_from('>13HII',m,o)
        kind,start,last,w,h,stride,maskoff,trigger,tx,ty,tw,th,sound,src,current=words
        if not w or not h: obs.append(None);continue
        # Descriptor's frame count is the last frame index, not a byte length.
        count=max(1,last)
        src-=0x5caf0
        frames=[]
        for frame in range(count):
            off=src+frame*stride
            if off+stride>len(objects):break
            im=planar(objects,off,w,h,4,pal,off+maskoff)
            name=f'style{style}/object{i}_{frame}.png';im.save(OUT/name);frames.append(name)
        obs.append({'frames':frames,'width':w,'height':h,'kind':kind,'trigger':trigger,'triggerX':tx,'triggerY':ty,'triggerWidth':tw,'triggerHeight':th,'sound':sound})
    styles.append({'palette':[list(x) for x in pal],'terrain':tiles,'objects':obs})

# Player sprite offsets and dimensions come from the original rendering routines.
sprites={}
pal=[rgb(u16(meta,i*2)) for i in range(16)]
specs={'walk':(0xcf08,16,10,3,9,540),'fall':(0xd340,16,10,3,4,240),
       'dig':(0xd520,16,14,4,16,0),'climb':(0xdc20,16,12,3,8,576),
       'hoist':(0xe0a0,16,13,4,8,832),'block':(0xf7e0,16,10,3,16,0),
       'build':(0xe720,16,13,4,16,1664),'bash':(0xfba0,16,10,4,32,2560),
       'mine':(0x117a0,16,13,3,32,2496),'exit':(0x138f8,16,10,3,16,0),
       'splat':(0x13cb8,16,10,3,16,0),'float':(0x10fa0,16,16,4,8,1024)}
# Some action tables include masks as an extra plane; palette pixels use the first 3.
for name,(src,w,h,planes,count,left) in specs.items():
    frames=[];stride=w//8*h*planes
    for direction,offset in ((1,0),(-1,left)):
        names=[]
        for i in range(count):
            off=src-0x400+offset+i*stride
            im=planar(code,off,w,h,planes-1,pal,off+(planes-1)*w//8*h)
            path=f'sprites/{name}_{direction}_{i}.png';(OUT/'sprites').mkdir(exist_ok=True);im.save(OUT/path);names.append(path)
        frames.append(names)
    sprites[name]={'width':w,'height':h,'frames':frames}

order=struct.unpack_from('>100H',meta,0x1bd0)
levels=[]
for idx,num in enumerate(order):
    number=num-1;b=(A/f'decoded/Level{number//4:03}').read_bytes()[number%4*2048:(number%4+1)*2048]
    head=struct.unpack('>16H',b[:32]);obs=[];terrain=[];steel=[]
    for o in range(32,288,8):
        x,y,i,flags=struct.unpack_from('>hhHH',b,o)
        if (x,y,i,flags)!=(0,0,0,0):obs.append({'x':x,'y':y,'id':i,'flags':flags})
    for o in range(288,1888,4):
        a,c=struct.unpack_from('>HH',b,o)
        if a==c==65535:break
        x=a&0x1fff;y=c>>7
        if y&256:y-=512
        terrain.append({'x':x,'y':y,'id':c&63,'upsideDown':bool(c&64),'erase':bool(a&0x4000),'behind':bool(a&0x8000)})
    for o in range(1888,2016,4):
        a,c=struct.unpack_from('>HH',b,o)
        if not (a or c):continue
        # Amiga steel uses the standard packed rectangle format.
        v=int.from_bytes(b[o:o+4],'big'); x=((v>>23)&511)*4; y=((v>>16)&127)*4
        steel.append({'x':x,'y':y,'width':((v>>12&15)+1)*4,'height':((v>>8&15)+1)*4})
    level={'index':idx,'sourceIndex':number,'rating':('Tame','Crazy','Wild','Wicked','Havoc')[idx//20],'number':idx%20+1,'title':b[2016:2048].decode('latin1').strip(),'releaseRate':head[0],'total':head[1],'required':head[2],'minutes':head[3],'skills':list(head[4:12]),'cameraX':head[12],'style':head[13],'objects':obs,'terrain':terrain,'steel':steel}
    levels.append(level)
    # Full-size preview and collision pixels used unchanged by the native game.
    im=Image.new('RGBA',(1632,168),(0,0,0,0)); collision=bytearray(1632*168)
    for t in terrain:
        desc=styles[head[13]]['terrain'][t['id']]
        if not desc:raise ValueError(('Missing tile',idx,t))
        tile=Image.open(OUT/desc['image']);
        if t['upsideDown']:tile=tile.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        for yy in range(tile.height):
            dy=t['y']+yy
            if not 0<=dy<168:continue
            for xx in range(tile.width):
                dx=t['x']+xx
                if not 0<=dx<1632:continue
                color=tile.getpixel((xx,yy))
                if not color[3]:continue
                pixel=dy*1632+dx
                if t['erase']: im.putpixel((dx,dy),(0,0,0,0));collision[pixel]=0
                elif not t['behind'] or not collision[pixel]:im.putpixel((dx,dy),color);collision[pixel]=1
    folder=OUT/'levels';folder.mkdir(exist_ok=True); im.save(folder/f'{idx:03}.png');(folder/f'{idx:03}.mask').write_bytes(collision)
(OUT/'catalog.json').write_text(json.dumps({'width':1632,'height':168,'styles':styles,'sprites':sprites,'levels':levels},indent=2))
print(f'Converted {len(levels)} ordered levels, {sum(x is not None for s in styles for x in s["terrain"])} terrain tiles and {sum(len(o["frames"]) for s in styles for o in s["objects"] if o)} object frames')
