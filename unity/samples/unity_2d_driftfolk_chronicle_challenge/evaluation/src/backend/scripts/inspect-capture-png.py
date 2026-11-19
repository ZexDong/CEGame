"""Read-only PNG decoding for author capture readiness, never visual scoring.

An exactly black RGB frame is unresolved observation, not proof that the host
or the product caused it and not a zero score. Preserve it for diagnosis.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image


def inspect(path):
    path=Path(path)
    if not path.is_file():
        return dict(valid=False,width=0,height=0,bytes=0,sha256="",all_black=None,error="file_missing")
    data=path.read_bytes()
    result=dict(valid=False,width=0,height=0,bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),all_black=None)
    try:
        with Image.open(path) as image:
            if image.format!="PNG":raise ValueError("not_png")
            image.verify()
        with Image.open(path) as image:
            image.load();rgb=image.convert("RGB");result["width"],result["height"]=rgb.size
            result["rgb_extrema"]=[list(pair) for pair in rgb.getextrema()]
            result["all_black"]=all(high==0 for low,high in rgb.getextrema())
            result["valid"]=result["width"]>0 and result["height"]>0
            result["observation_status"]="all_black_frame_requires_diagnosis" if result["all_black"] else "decoded_nonblack_frame"
            result["root_cause"]="unattributed" if result["all_black"] else None
    except Exception as error:
        result["error"]=type(error).__name__+": "+str(error)
    return result


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--path",type=Path,required=True)
    args=parser.parse_args();print(json.dumps(inspect(args.path),separators=(",",":")))
