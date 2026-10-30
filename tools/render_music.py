"""Render original music offline using its own 68000 replay code and sampled instruments.
Requires machine68k and numpy only during conversion; the Mac game plays WAV natively.
Paula mixing uses PAL clocks, sample loops, pitch and volume; analog filtering is approximated.
"""
from pathlib import Path
import json,struct,wave,argparse
import numpy as np
from machine68k import Machine,CPUType,Register
ROOT=Path(__file__).resolve().parents[1];A=ROOT/'Assets'
class Replay:
 def __init__(self):
  self.machine=Machine(CPUType.M68000,16384);self.cpu=self.machine.cpu;self.mem=self.machine.mem
  self.mem.w32(0,0x3ff000);self.mem.w32(4,0x3fe000);self.cpu.execute(self.cpu.pulse_reset())
  self.mem.w_block(0x400,(A/'decoded/Code').read_bytes())
  self.end=self.machine.create_execute_end('return');self.trap=self.machine.traps.alloc(lambda op,pc:self.end)
  self.mem.w16(0x3fe000,0xa000|self.trap)
  self.regs=bytearray(0x1000);self.cia={};self.channels=[{'active':False,'data':np.zeros(2),'phase':0.0} for _ in range(4)]
  self.mem.set_special_range_write_funcs(0xdf0000,w8=lambda a,v:self.write(a,v,1),w16=lambda a,v:self.write(a,v,2),w32=lambda a,v:self.write(a,v,4))
  self.mem.set_special_range_read_funcs(0xdf0000,r8=lambda a:0,r16=lambda a:0,r32=lambda a:0)
  self.mem.set_special_range_write_funcs(0xbf0000,w8=lambda a,v:self.cia.__setitem__(a,v),w16=lambda a,v:None,w32=lambda a,v:None)
  self.mem.set_special_range_read_funcs(0xbf0000,r8=lambda a:0,r16=lambda a:0,r32=lambda a:0)
 def u16(self,o):return int.from_bytes(self.regs[o:o+2],'big')
 def u32(self,o):return int.from_bytes(self.regs[o:o+4],'big')
 def reload(self,i):
  ch=self.channels[i];o=0xa0+i*16;ptr=self.u32(o);length=max(2,self.u16(o+4)*2)
  if ptr+length>0x1000000:raise ValueError('Invalid Paula pointer')
  ch['data']=np.frombuffer(self.mem.r_block(ptr,length),dtype=np.int8).astype(np.float64)/128
  ch['phase']=0.0
 def write(self,addr,value,size):
  if not 0xdff000<=addr<0xe00000:return
  o=addr-0xdff000;self.regs[o:o+size]=value.to_bytes(size,'big')
  if o==0x96:
   for i,ch in enumerate(self.channels):
    if value&(1<<i):
     if value&0x8000:
      if not ch['active']:self.reload(i)
      ch['active']=True
     else:ch['active']=False
 def call(self,offset,**regs):
  for name,value in regs.items():self.cpu.w_reg(getattr(Register,name.upper()),value)
  self.cpu.w_sr(0x2000);self.cpu.w_sp(0x3ff000);self.mem.w32(0x3ff000,0x3fe000);self.cpu.w_pc(0x17206+offset)
  result=self.machine.execute(1000000)
  if result.result is not self.end:raise RuntimeError(f'Replay did not return: {result}, PC={self.cpu.r_pc():x}')
 def setup(self,number):
  self.call(0)
  meta=(A/'decoded/leveldata').read_bytes();base=0x2184c-0x1f760
  record=next(meta[o:o+28] for o in range(base,base+6*28,28) if meta[o:o+12].split(b'\0')[0]==f'tune{number}'.encode())
  tune=(A/f'decoded/tune{number}').read_bytes();self.mem.w_block(0x200000,tune)
  ptr=0x210000;previous=None
  for slot,index in enumerate(record[12:28],1):
   if index:
    off=0x21498-0x1f760+(index-1)*12;name=meta[off:off+12].split(b'\0')[0].decode()
    data=(A/'raw'/name).read_bytes();self.mem.w_block(ptr,data);previous=ptr;ptr+=(len(data)+3)&~3
   if previous is not None:self.call(4,d0=slot,a1=previous)
  self.call(0xc,d0=1,a2=0x200000);self.call(0x18,d0=1)
  timer=self.cia.get(0xbfe401,0)+256*self.cia.get(0xbfe501,0)
  self.dt=timer/709378.92 if timer else 1/50
  print('Tune',number,'interrupt Hz',round(1/self.dt,3),flush=True)
 def mix(self,count,rate=44100):
  result=np.zeros((count,2),dtype=np.float64)
  for i,ch in enumerate(self.channels):
   if not ch['active']:continue
   o=0xa0+i*16;period=max(1,self.u16(o+6));volume=min(64,self.u16(o+8))/64
   speed=3546894.6/period/rate;pos=0
   while pos<count:
    if ch['phase']>=len(ch['data']):
     overflow=ch['phase']-len(ch['data']);self.reload(i);ch['phase']=overflow%len(ch['data'])
    size=min(count-pos,max(1,int(np.ceil((len(ch['data'])-ch['phase'])/speed))))
    indices=(ch['phase']+np.arange(size)*speed).astype(np.int64)
    indices=np.minimum(indices,len(ch['data'])-1)
    v=ch['data'][indices]*volume*0.30
    pan=0 if i in (0,3) else 1
    result[pos:pos+size,pan]+=v;result[pos:pos+size,1-pan]+=v*0.35
    ch['phase']+=size*speed;pos+=size
  return result
 def close(self):self.machine.cleanup()

def render(number,seconds):
 r=Replay();r.setup(number);chunks=[];total=0;seen={};loop=None
 for tick in range(int(seconds/r.dt)):
  r.call(0x40)
  end=round((tick+1)*r.dt*44100);chunks.append(r.mix(end-total));total=end
  signature=bytes(r.mem.r_block(0x17fa4,56))+bytes(r.mem.r_block(0x17bec,2))
  if signature in seen and total-seen[signature]>44100*5:
   loop=(seen[signature],total);print('Sequence loop',number,loop[0]/44100,loop[1]/44100,flush=True);break
  seen.setdefault(signature,total)
  if tick%3000==0:print(number,round(total/44100,1),'seconds',flush=True)
 audio=np.concatenate(chunks);r.close()
 if loop:audio=audio[loop[0]:loop[1]]
 if np.max(np.abs(audio))==0:raise ValueError('Silent music')
 audio=np.clip(audio,-1,1)
 # Gentle low-pass approximates the Amiga output stage and reduces resampling aliasing.
 audio[2:]=audio[2:]*0.5+audio[1:-1]*0.3+audio[:-2]*0.2
 out=A/'music';out.mkdir(exist_ok=True)
 with wave.open(str(out/f'tune{number}.wav'),'wb') as f:
  f.setnchannels(2);f.setsampwidth(2);f.setframerate(44100);f.writeframes((audio*32767).astype('<i2').tobytes())
 print('Rendered',number,total/44100,'seconds; peak',float(np.abs(audio).max()),flush=True)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--tune',type=int,default=0);p.add_argument('--seconds',type=float,default=180);args=p.parse_args()
 for number in ([args.tune] if args.tune else range(1,7)):render(number,args.seconds)
