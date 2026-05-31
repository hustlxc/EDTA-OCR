import pandas as pd
import glob
import os

a=glob.glob("captures/*.png")

aa=[os.path.basename(e).replace('.png', '') for e in a]
z=pd.DataFrame({"住院号":aa, "original_path":a})

x=pd.read_csv("EDTA_OCR_2026-05-30.csv")

x['new_path'] = [f"captures/{k}.png" for k in x['子弹头编号']]

y=x.merge(z)

for src, dst in zip(y.original_path, y.new_path):
    os.rename(src, dst)

