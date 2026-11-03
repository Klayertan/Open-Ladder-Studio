"""Wrap an unmodified, user-authorized desktop screenshot in a PDF page."""
from pathlib import Path
import argparse
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader
parser=argparse.ArgumentParser()
parser.add_argument('screenshot',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args()
image=ImageReader(str(args.screenshot))
width,height=image.getSize()
args.output.parent.mkdir(parents=True,exist_ok=True)
pdf=canvas.Canvas(str(args.output),pagesize=(width/2,height/2),pageCompression=1)
pdf.setTitle('Exercise 10 - actual Open Ladder Studio execution screen')
pdf.setSubject('Unmodified macOS desktop screenshot including the system clock; native simulator, not Renri')
pdf.drawImage(image,0,0,width=width/2,height=height/2,mask='auto')
pdf.showPage();pdf.save()
print(args.output)
