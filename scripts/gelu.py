import numpy as np

i = np.arange(256, dtype=np.uint8)
x = i.view(np.int8).astype(np.float64)

gelu = x * 0.5 * (1 + np.tanh(np.sqrt(2/np.pi) * (x + 0.044715 * x**3)))

lut = np.clip(np.round(gelu*256), -32768, 32767).astype(np.int16)

with open("./lut/gelu_q88.hex", "w") as f:
    for value in lut:
        f.write(f"{value & 0xFFFF:04x}\n")
