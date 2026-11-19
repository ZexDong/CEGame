"""Offline local OCR of a preserved native frame plus a declared 2x observation derivative."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys
from PIL import Image
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument("--frame",type=Path,required=True);p.add_argument("--output",type=Path,required=True);args=p.parse_args()
    frame=args.frame.resolve();out=args.output.resolve()
    if out.exists():raise ValueError("Preserve existing OCR evidence")
    out.mkdir(parents=True)
    before=sha(frame)
    with Image.open(frame) as source:
        width,height=source.size
        if width<1 or height<1 or width>2600 or height>2600:raise ValueError("Frame outside qualified OCR bounds")
        scale=min(2.0,2560/max(width,height))
        target=(round(width*scale),round(height*scale))
        derivative=source.convert("RGB").resize(target,Image.Resampling.NEAREST)
        derived=out/"observation-2x.png";derivative.save(derived)
    script=Path(__file__).with_name("read-derived-image-text.ps1")
    pwsh=Path(os.environ.get("SystemRoot",r"C:\Windows"))/"System32/WindowsPowerShell/v1.0/powershell.exe"
    argv=[str(pwsh),"-NoProfile","-NonInteractive","-File",str(script),"-ImagePath",str(derived),"-OutputPath",str(out/"raw-ocr.json")]
    env=dict(os.environ)
    # Unity/Python may inherit PowerShell 7's PSModulePath. A Windows PowerShell
    # 5.1 child needs its own built-in modules, not incompatible Core manifests.
    env["PSModulePath"]=str(pwsh.parent/"Modules")
    process=subprocess.run(argv,capture_output=True,timeout=90,env=env,creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0))
    (out/"stdout.log").write_bytes(process.stdout);(out/"stderr.log").write_bytes(process.stderr)
    if process.returncode:raise ValueError("Local OCR process failed: "+str(process.returncode))
    raw=json.loads((out/"raw-ocr.json").read_text(encoding="utf-8-sig"))
    if not raw.get("valid") or raw.get("source_sha256")!=sha(derived):raise ValueError("OCR image receipt changed")
    lines=[];seen=set()
    for line in raw["lines"]:
        words=[]
        for word in line["words"]:
            words.append(dict(text=word["text"],x=word["x"]/scale,y=word["y"]/scale,width=word["width"]/scale,height=word["height"]/scale))
        key=tuple((w["text"],round(w["x"],1),round(w["y"],1),round(w["width"],1),round(w["height"],1)) for w in words)
        if key in seen:continue
        seen.add(key);lines.append(dict(text=line["text"],words=words))
    if sha(frame)!=before:raise ValueError("Native source frame changed")
    result=dict(schema="native-frame-local-ocr-observation/v1",valid=True,frame=str(frame),frame_sha256=before,
        width=width,height=height,derived_image=str(derived),derived_sha256=sha(derived),scale=scale,
        interpolation="nearest-neighbour geometric observation derivative only",coordinate_mapping="native_rect=derived_rect/scale",
        source_frame_unchanged=True,not_d6_replacement=True,language=raw["language"],ocr_script_sha256=sha(script),
        powershell_module_policy="Windows PowerShell 5.1 built-in modules only in this child",
        text=" ".join(line["text"] for line in lines),lines=lines,process_exit=process.returncode,
        process_stdout_sha256=sha(out/"stdout.log"),process_stderr_sha256=sha(out/"stderr.log"),
        limitations="OCR may be uncertain; missing recognition is not by itself proof of missing product text.")
    (out/"result.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    print(json.dumps({"valid":True,"result":str(out/"result.json"),"text":result["text"],"language":result["language"]},ensure_ascii=False))
if __name__=="__main__":
    try:main()
    except (ValueError,OSError,KeyError,subprocess.TimeoutExpired) as error:
        print(json.dumps({"valid":False,"error":str(error)},ensure_ascii=False),file=sys.stderr);raise SystemExit(3)
