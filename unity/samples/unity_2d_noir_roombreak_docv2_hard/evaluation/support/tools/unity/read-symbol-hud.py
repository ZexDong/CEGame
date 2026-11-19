"""Read small filled/empty HUD symbols from actual pixels, anchored by OCR labels."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image


def components(image, box):
    left, top, right, bottom = box
    pixels = image.load()
    mask = {(x, y) for y in range(max(0, top), min(image.height, bottom))
            for x in range(max(0, left), min(image.width, right))
            if max(pixels[x, y]) > 180 and min(pixels[x, y]) > 65}
    result = []
    while mask:
        first = mask.pop(); todo = [first]; points = {first}
        while todo:
            x, y = todo.pop()
            for point in ((x+1, y), (x-1, y), (x, y+1), (x, y-1)):
                if point in mask:
                    mask.remove(point); todo.append(point); points.add(point)
        if len(points) < 4:
            continue
        xs, ys = zip(*points)
        x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
        cx, cy = (x0+x1)//2, (y0+y1)//2
        center = sum((x, y) in points for x in range(cx-1, cx+2) for y in range(cy-1, cy+2))/9
        result.append(dict(x=x0, y=y0, width=x1-x0+1, height=y1-y0+1,
                           pixels=len(points), center_fill=center))
    return sorted(result, key=lambda x: x['x'])


def observe(image, ocr):
    words = [word for line in ocr['lines'] for word in line['words']]
    facts = dict(observed_room=-1, observed_bonds=-1, observed_charges=-1, symbol_regions={})
    def anchor(name):
        candidates = [w for w in words if w['text'].upper() == name and w['y'] < image.height*.2]
        return min(candidates, key=lambda w: w['y']) if candidates else None
    for name, field in [('BONDS', 'observed_bonds'), ('DASH', 'observed_charges')]:
        word = anchor(name)
        if word is None: continue
        h = word['height']; x = int(word['x']+word['width']+3); y = int(word['y'])-2
        regions = components(image, (x, y, int(x+h*4.3), int(y+h+4)))
        if len(regions) != 3: continue
        if not all(h*.25 <= r['width'] <= h*.9 and h*.25 <= r['height'] <= h*.8 for r in regions): continue
        if max(r['width'] for r in regions)-min(r['width'] for r in regions) > 2: continue
        if max(r['y'] for r in regions)-min(r['y'] for r in regions) > 2: continue
        if not all(r['center_fill'] >= .75 or r['center_fill'] <= .25 for r in regions): continue
        facts[field] = sum(r['center_fill'] >= .75 for r in regions)
        facts['symbol_regions'][name] = regions
    word = anchor('ROOM')
    if word:
        h = word['height']; x = int(word['x']+word['width']+3); y = int(word['y'])-2
        regions = components(image, (x, y, int(x+h*6), int(y+h+4)))
        # I/II/III have vertical bars before the slash. IV/V are not inferred
        # from a partial glyph; the regular OCR path continues to handle them.
        bars=[]
        for region in regions:
            if region['height'] >= h*.7 and region['width'] <= h*.3:
                bars.append(region)
            else:
                break
        following = regions[len(bars):]
        slash = following[0] if following else None
        if 1 <= len(bars) <= 3 and slash and h*.3 < slash['width'] < h*.6 and slash['height'] >= h*.7:
            facts['observed_room'] = len(bars)-1
            facts['symbol_regions']['ROOM'] = bars
    facts['valid'] = all(facts[key] >= 0 for key in ('observed_room','observed_bonds','observed_charges'))
    return facts


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--image',type=Path,required=True)
    parser.add_argument('--ocr',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();ocr=json.loads(args.ocr.read_text(encoding='utf-8-sig'))
    image_hash=hashlib.sha256(args.image.read_bytes()).hexdigest()
    if image_hash != ocr['source_sha256']: raise ValueError('OCR belongs to another image')
    result=observe(Image.open(args.image).convert('RGB'),ocr)
    result.update(method='ocr-anchored-filled-symbols-v1',source_sha256=image_hash,
                  ocr_sha256=hashlib.sha256(args.ocr.read_bytes()).hexdigest())
    args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
    print(json.dumps(result))


if __name__=='__main__': main()
