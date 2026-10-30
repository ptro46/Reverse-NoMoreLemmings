from capstone import *
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=(root/'Assets/decoded/Code').read_bytes(); md=Cs(CS_ARCH_M68K,CS_MODE_BIG_ENDIAN|CS_MODE_M68K_000);md.skipdata=True
with (root/'work/code.asm').open('w') as f:
 for i in md.disasm(p,0x400):f.write(f'{i.address:06x} {i.mnemonic:12} {i.op_str}\n')
import re
for m in re.finditer(rb'[ -~]{6,}',p):
 if any(s in m.group().lower() for s in (b'ground',b'object',b'level',b'tune',b'tame',b'crazy')): print(hex(m.start()),m.group())
