import numpy as np
import os

i = np.arange(256, dtype=np.uint8)
x = i.view(np.int8).astype(np.float64)

exponential = np.exp(x)

lut = np.clip(np.round(exponential*256), -32768, 32767).astype(np.int16)
unsigned_lut = lut.view(np.uint16)

os.makedirs("lut", exist_ok=True)

with open("./lut/exp_q88.hex", "w") as f:
    for value in unsigned_lut:
        f.write(f"{value & 0xFFFF:04x}\n")
